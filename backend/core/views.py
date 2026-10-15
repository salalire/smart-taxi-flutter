"""
API views for the Ethiopian Public Minibus Monitoring System.
"""

from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .models import (
    Driver, Inspector, Passenger, Zone, Route,
    RouteViolation, PassengerReport, PassengerDemandReport,
    StopCheckIn, InspectorFieldObservation,
    RelocationRequest, InspectorDispatch,
)
from .serializers import (
    RegisterSerializer, CustomTokenObtainPairSerializer,
    DriverSerializer, DriverStatusSerializer,
    InspectorSerializer, ZoneSerializer, RouteSerializer,
    RouteViolationSerializer, ViolationRecordSerializer,
    PassengerReportSerializer, PassengerDemandReportSerializer,
    StopCheckInSerializer, InspectorFieldObservationSerializer,
    RelocationRequestSerializer, RelocationRequestCreateSerializer, RelocationDecisionSerializer,
    InspectorDispatchSerializer, DispatchRespondSerializer,
    BusLookupSerializer,
)
from distribution.logic import evaluate_zone, buses_in_zone, run_distribution


# ---------------------------------------------------------------------------
# Permissions helpers
# ---------------------------------------------------------------------------

def is_driver(user):
    return user.role == 'driver'

def is_inspector(user):
    return user.role == 'inspector'

def is_ministry(user):
    return user.role == 'ministry_admin'

def is_passenger(user):
    return user.role == 'passenger'


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

@api_view(['POST'])
@permission_classes([AllowAny])
def register(request):
    serializer = RegisterSerializer(data=request.data)
    if serializer.is_valid():
        user = serializer.save()
        return Response(
            {'message': f'Account created for {user.username}.', 'role': user.role},
            status=status.HTTP_201_CREATED
        )
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class LoginView(TokenObtainPairView):
    serializer_class   = CustomTokenObtainPairSerializer
    permission_classes = [AllowAny]


@api_view(['GET'])
@permission_classes([AllowAny])
def route_list(request):
    """Public list of all active routes — used on the register screen route picker."""
    routes = Route.objects.filter(is_active=True).select_related('zone')
    data = [
        {
            'id':   r.id,
            'name': r.name,
            'zone': r.zone.name if r.zone else None,
            'official_fare': str(r.official_fare),
        }
        for r in routes
    ]
    return Response(data)


# ---------------------------------------------------------------------------
# Driver endpoints
# ---------------------------------------------------------------------------

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def driver_update_location(request):
    """
    REST fallback for GPS updates when WebSocket is unavailable.
    The Android app uses WebSocket primarily — this is the backup.
    Called by the app if WebSocket connection drops.
    """
    try:
        driver = request.user.driver_profile
    except Driver.DoesNotExist:
        return Response({'error': 'Driver profile not found.'}, status=404)

    lat = request.data.get('lat')
    lng = request.data.get('lng')

    if lat is None or lng is None:
        return Response({'error': 'lat and lng are required.'}, status=400)

    try:
        lat = float(lat)
        lng = float(lng)
    except (TypeError, ValueError):
        return Response({'error': 'lat and lng must be numbers.'}, status=400)

    location_update = driver.update_location(lat, lng)

    response_data = {
        'status':      driver.status,
        'is_on_route': location_update.is_on_route,
        'lat':         lat,
        'lng':         lng,
    }

    if not location_update.is_on_route:
        response_data['alert'] = 'You have left your assigned route. Please return immediately.'

    return Response(response_data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def driver_my_route(request):
    """Driver fetches their assigned route with all waypoints."""
    try:
        driver = request.user.driver_profile
    except Driver.DoesNotExist:
        return Response({'error': 'Driver profile not found.'}, status=404)

    if not driver.assigned_route:
        return Response({'error': 'No route assigned yet. Contact the Ministry.'}, status=404)

    return Response(RouteSerializer(driver.assigned_route).data)


@api_view(['PATCH'])
@permission_classes([IsAuthenticated])
def driver_update_status(request):
    """Driver sets themselves online (on_route) or offline."""
    try:
        driver = request.user.driver_profile
    except Driver.DoesNotExist:
        return Response({'error': 'Driver profile not found.'}, status=404)

    serializer = DriverStatusSerializer(driver, data=request.data, partial=True)
    if serializer.is_valid():
        serializer.save()
        return Response({'status': driver.status})
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def driver_request_relocation(request):
    """
    Driver requests a temporary relocation to a different zone.
    Goes to Ministry for approval.
    """
    try:
        driver = request.user.driver_profile
    except Driver.DoesNotExist:
        return Response({'error': 'Driver profile not found.'}, status=404)

    serializer = RelocationRequestCreateSerializer(data=request.data)
    if not serializer.is_valid():
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    to_zone   = serializer.validated_data['to_zone']
    from_zone = driver.assigned_route.zone if driver.assigned_route else None

    if not from_zone:
        return Response({'error': 'Driver has no assigned route/zone.'}, status=400)

    relocation = RelocationRequest.objects.create(
        driver=driver,
        from_zone=from_zone,
        to_zone=to_zone,
        reason=serializer.validated_data['reason'],
        initiated_by=RelocationRequest.INITIATED_DRIVER,
    )
    return Response(RelocationRequestSerializer(relocation).data, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def driver_relocation_status(request):
    """Driver checks the status of their latest relocation request."""
    try:
        driver = request.user.driver_profile
    except Driver.DoesNotExist:
        return Response({'error': 'Driver profile not found.'}, status=404)

    relocation = RelocationRequest.objects.filter(driver=driver).order_by('-requested_at').first()
    if not relocation:
        return Response({'message': 'No relocation requests found.'})

    return Response(RelocationRequestSerializer(relocation).data)


# ---------------------------------------------------------------------------
# Passenger endpoints
# ---------------------------------------------------------------------------

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def zone_simple_list(request):
    """Simple zone list for mobile app dropdowns — just id and name."""
    zones = Zone.objects.all().values('id', 'name')
    return Response(list(zones))


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def zone_demand_summary(request):
    """
    Returns demand signal summary per zone for the passenger app map.
    Shows active check-ins and recent demand reports per zone.
    Passengers use this to see which stops are busy.
    """
    from distribution.logic import weighted_demand_score

    zones  = Zone.objects.all()
    cutoff = timezone.now() - timezone.timedelta(minutes=30)
    data   = []

    for zone in zones:
        active_checkins = StopCheckIn.objects.filter(zone=zone, is_active=True).count()
        recent_reports  = PassengerDemandReport.objects.filter(
            zone=zone, created_at__gte=cutoff
        ).count()
        demand_score = weighted_demand_score(zone)
        bus_count    = len(buses_in_zone(zone))
        zone_status  = evaluate_zone(zone)

        data.append({
            # Keys match Zone.fromJson in the Flutter app
            'id':              zone.id,
            'name':            zone.name,
            'center_lat':      zone.center_latitude,
            'center_lng':      zone.center_longitude,
            'radius_km':       zone.radius_km,
            'status':          zone_status,
            'bus_count':       bus_count,
            # demand_count = active check-ins + recent demand reports
            'demand_count':    active_checkins + recent_reports,
            # Extra detail kept for future use
            'active_checkins': active_checkins,
            'recent_reports':  recent_reports,
            'demand_score':    round(demand_score, 2),
        })

    return Response(data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def nearby_buses(request):
    """
    Return buses currently operating near a given location.
    Query params: lat, lng, radius_km (optional, default 2)
    """
    try:
        lat    = float(request.query_params.get('lat'))
        lng    = float(request.query_params.get('lng'))
        radius = float(request.query_params.get('radius_km', 2.0))
    except (TypeError, ValueError):
        return Response({'error': 'lat and lng query parameters are required.'}, status=400)

    from distribution.logic import haversine_km
    all_drivers = Driver.objects.exclude(
        status=Driver.STATUS_OFFLINE
    ).exclude(
        current_latitude=None
    ).select_related('user', 'assigned_route')

    nearby = [
        d for d in all_drivers
        if haversine_km(lat, lng, d.current_latitude, d.current_longitude) <= radius
    ]

    return Response(DriverSerializer(nearby, many=True).data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def submit_passenger_report(request):
    """Passenger reports a violation by plate number."""
    try:
        passenger = request.user.passenger_profile
    except Passenger.DoesNotExist:
        return Response({'error': 'Passenger profile not found.'}, status=404)

    serializer = PassengerReportSerializer(data=request.data)
    if not serializer.is_valid():
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    report = serializer.save(reporter=passenger)
    return Response(PassengerReportSerializer(report).data, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def submit_demand_report(request):
    """
    Passenger reports demand or supply conditions at a stop.
    Weight is computed automatically based on reporter GPS proximity to the zone.
    """
    try:
        passenger = request.user.passenger_profile
    except Passenger.DoesNotExist:
        return Response({'error': 'Passenger profile not found.'}, status=404)

    serializer = PassengerDemandReportSerializer(data=request.data)
    if not serializer.is_valid():
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    report = serializer.save(reporter=passenger)

    from distribution.tasks import run_distribution_task
    run_distribution_task.delay()

    return Response(PassengerDemandReportSerializer(report).data, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def stop_checkin(request):
    """
    Passenger checks in at a bus stop — one tap to say I am waiting here.
    Creates a StopCheckIn that counts as real-time demand for the zone.
    Expires automatically after 30 minutes.
    """
    try:
        passenger = request.user.passenger_profile
    except Passenger.DoesNotExist:
        return Response({'error': 'Passenger profile not found.'}, status=404)

    serializer = StopCheckInSerializer(data=request.data)
    if not serializer.is_valid():
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    StopCheckIn.objects.filter(passenger=passenger, is_active=True).update(
        is_active=False,
        checked_out_at=timezone.now(),
    )

    checkin = serializer.save(passenger=passenger)

    from distribution.tasks import run_distribution_task
    run_distribution_task.delay()

    return Response(StopCheckInSerializer(checkin).data, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def stop_checkout(request):
    """Passenger boarded a bus — cancel their active check-in."""
    try:
        passenger = request.user.passenger_profile
    except Passenger.DoesNotExist:
        return Response({'error': 'Passenger profile not found.'}, status=404)

    checkin = StopCheckIn.objects.filter(passenger=passenger, is_active=True).first()
    if not checkin:
        return Response({'message': 'No active check-in found.'})

    checkin.checkout()
    return Response({'message': 'Checked out. Enjoy your ride!'})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def inspector_list(request):
    """
    Return all inspectors with id, badge_number, and assigned_zone name.
    Used by Ministry when manually dispatching an inspector to a violation.
    """
    inspectors = Inspector.objects.select_related('user', 'assigned_zone').all()
    data = [
        {
            'id':            i.id,
            'badge_number':  i.badge_number,
            'username':      i.user.username,
            'assigned_zone': i.assigned_zone.name if i.assigned_zone else None,
            'is_available':  i.is_available,
        }
        for i in inspectors
    ]
    return Response(data)


# ---------------------------------------------------------------------------
# Inspector endpoints
# ---------------------------------------------------------------------------

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def inspector_bus_lookup(request, plate_number):
    """
    Inspector scans/enters a plate number and gets full bus info:
    current status, assigned route, compliance score, recent violations,
    and whether the bus has an active relocation permit.
    """
    try:
        driver = Driver.objects.select_related(
            'user', 'assigned_route'
        ).prefetch_related(
            'violations', 'relocation_requests'
        ).get(license_plate__iexact=plate_number)
    except Driver.DoesNotExist:
        return Response({'error': f'No bus found with plate {plate_number}.'}, status=404)

    return Response(BusLookupSerializer(driver).data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def inspector_record_violation(request):
    """
    Inspector records a violation on the spot.
    Can confirm an existing open violation or create a new one.
    """
    try:
        inspector = request.user.inspector_profile
    except Inspector.DoesNotExist:
        return Response({'error': 'Inspector profile not found.'}, status=404)

    serializer = ViolationRecordSerializer(data=request.data)
    if not serializer.is_valid():
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    plate  = serializer.validated_data['plate_number']
    action = serializer.validated_data['action']
    notes  = serializer.validated_data.get('notes', '')

    try:
        driver = Driver.objects.get(license_plate__iexact=plate)
    except Driver.DoesNotExist:
        return Response({'error': f'No driver found with plate {plate}.'}, status=404)

    violation = RouteViolation.objects.filter(
        driver=driver,
        status__in=[RouteViolation.STATUS_OPEN, RouteViolation.STATUS_DISPATCHED]
    ).order_by('-detected_at').first()

    if not violation:
        violation = RouteViolation.objects.create(
            driver=driver,
            route=driver.assigned_route,
            latitude=driver.current_latitude or 0,
            longitude=driver.current_longitude or 0,
        )

    if action == 'confirm':
        violation.confirm(inspector=inspector, notes=notes)
        return Response({'message': f'Violation confirmed for plate {plate}. Compliance score updated.'})
    else:
        violation.dismiss(inspector=inspector, notes=notes)
        return Response({'message': f'Violation dismissed for plate {plate}.'})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def inspector_dispatches(request):
    """Inspector gets their pending dispatch alerts."""
    try:
        inspector = request.user.inspector_profile
    except Inspector.DoesNotExist:
        return Response({'error': 'Inspector profile not found.'}, status=404)

    dispatches = InspectorDispatch.objects.filter(
        inspector=inspector,
        status__in=[InspectorDispatch.STATUS_SENT, InspectorDispatch.STATUS_ACKNOWLEDGED]
    ).select_related('violation', 'violation__driver', 'violation__route')

    return Response(InspectorDispatchSerializer(dispatches, many=True).data)


@api_view(['PATCH'])
@permission_classes([IsAuthenticated])
def inspector_respond_dispatch(request, dispatch_id):
    """Inspector acknowledges or completes a dispatch."""
    try:
        inspector = request.user.inspector_profile
        dispatch  = InspectorDispatch.objects.get(pk=dispatch_id, inspector=inspector)
    except Inspector.DoesNotExist:
        return Response({'error': 'Inspector profile not found.'}, status=404)
    except InspectorDispatch.DoesNotExist:
        return Response({'error': 'Dispatch not found.'}, status=404)

    serializer = DispatchRespondSerializer(data=request.data)
    if not serializer.is_valid():
        return Response(serializer.errors, status=400)

    action = serializer.validated_data['action']
    if action == 'acknowledge':
        dispatch.acknowledge()
        return Response({'message': 'Dispatch acknowledged. Head to the location.'})
    else:
        dispatch.complete()
        return Response({'message': 'Dispatch completed.'})


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def inspector_field_observation(request):
    """
    Inspector files a field observation beyond violations.
    Examples: bus not stopping, stop abandoned, GPS disabled, overcrowding.
    """
    try:
        inspector = request.user.inspector_profile
    except Inspector.DoesNotExist:
        return Response({'error': 'Inspector profile not found.'}, status=404)

    serializer = InspectorFieldObservationSerializer(data=request.data)
    if not serializer.is_valid():
        return Response(serializer.errors, status=400)

    observation = serializer.save(inspector=inspector)

    demand_types = [
        InspectorFieldObservation.TYPE_OVERCROWDING,
        InspectorFieldObservation.TYPE_STOP_ABANDONED,
    ]
    if observation.observation_type in demand_types:
        from distribution.tasks import run_distribution_task
        run_distribution_task.delay()

    return Response(
        InspectorFieldObservationSerializer(observation).data,
        status=status.HTTP_201_CREATED
    )


# ---------------------------------------------------------------------------
# Ministry endpoints
# ---------------------------------------------------------------------------

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def ministry_demand_reports(request):
    """All passenger demand reports — high demand, long wait, oversupply etc."""
    from core.models import PassengerDemandReport
    from core.serializers import PassengerDemandReportSerializer

    qs = PassengerDemandReport.objects.select_related(
        'reporter', 'zone'
    ).order_by('-created_at')

    return Response(PassengerDemandReportSerializer(qs, many=True).data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def ministry_passenger_reports(request):
    """All passenger violation reports."""
    from core.models import PassengerReport
    from core.serializers import PassengerReportSerializer

    qs = PassengerReport.objects.select_related(
        'reporter', 'zone'
    ).order_by('-created_at')

    report_type = request.query_params.get('report_type')
    if report_type:
        qs = qs.filter(report_type=report_type)

    return Response(PassengerReportSerializer(qs, many=True).data)


@api_view(['PATCH'])
@permission_classes([IsAuthenticated])
def ministry_mark_report_reviewed(request, report_id):
    """Ministry marks a passenger report as reviewed."""
    from core.models import PassengerReport
    try:
        report = PassengerReport.objects.get(pk=report_id)
        report.is_reviewed = True
        report.save(update_fields=['is_reviewed'])
        return Response({'message': 'Marked as reviewed.'})
    except PassengerReport.DoesNotExist:
        return Response({'error': 'Not found.'}, status=404)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def ministry_observations(request):
    """All field observations filed by inspectors."""
    from core.models import InspectorFieldObservation
    from core.serializers import InspectorFieldObservationSerializer

    qs = InspectorFieldObservation.objects.select_related(
        'inspector', 'zone'
    ).order_by('-created_at')

    reviewed = request.query_params.get('reviewed')
    if reviewed is not None:
        qs = qs.filter(is_reviewed=(reviewed == 'true'))

    return Response(InspectorFieldObservationSerializer(qs, many=True).data)


@api_view(['PATCH'])
@permission_classes([IsAuthenticated])
def ministry_mark_observation_reviewed(request, observation_id):
    """Ministry marks an observation as reviewed."""
    from core.models import InspectorFieldObservation
    try:
        obs = InspectorFieldObservation.objects.get(pk=observation_id)
        obs.is_reviewed = True
        obs.save(update_fields=['is_reviewed'])
        return Response({'message': 'Marked as reviewed.'})
    except InspectorFieldObservation.DoesNotExist:
        return Response({'error': 'Not found.'}, status=404)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def ministry_live_buses(request):
    """All buses with current position and compliance status."""
    drivers = Driver.objects.exclude(
        status=Driver.STATUS_OFFLINE
    ).select_related('user', 'assigned_route', 'assigned_route__zone')
    return Response(DriverSerializer(drivers, many=True).data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def ministry_violations(request):
    """All violations with optional status filter."""
    qs = RouteViolation.objects.select_related(
        'driver', 'route', 'recorded_by'
    ).all()

    status_filter = request.query_params.get('status')
    if status_filter:
        qs = qs.filter(status=status_filter)

    return Response(RouteViolationSerializer(qs, many=True).data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def ministry_dispatch_inspector(request, violation_id):
    """Ministry manually dispatches an inspector to a violation location."""
    try:
        violation = RouteViolation.objects.get(pk=violation_id)
    except RouteViolation.DoesNotExist:
        return Response({'error': 'Violation not found.'}, status=404)

    inspector_id = request.data.get('inspector_id')
    try:
        inspector = Inspector.objects.get(pk=inspector_id)
    except Inspector.DoesNotExist:
        return Response({'error': 'Inspector not found.'}, status=404)

    dispatch = InspectorDispatch.objects.create(
        inspector=inspector,
        violation=violation,
        auto_dispatched=False,
    )
    dispatch.acknowledge()

    from realtime.push import push_dispatch_to_inspector
    push_dispatch_to_inspector(inspector, dispatch)

    return Response(InspectorDispatchSerializer(dispatch).data, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def ministry_zones(request):
    """All zones with current supply, demand, and status."""
    zones = Zone.objects.prefetch_related('thresholds').all()
    data  = []
    for zone in zones:
        zone_status = evaluate_zone(zone)
        bus_count   = len(buses_in_zone(zone))
        serializer  = ZoneSerializer(zone)
        zone_data   = serializer.data
        zone_data['status']    = zone_status
        zone_data['bus_count'] = bus_count
        data.append(zone_data)
    return Response(data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def ministry_pending_relocations(request):
    """All pending relocation requests waiting for Ministry decision."""
    relocations = RelocationRequest.objects.filter(
        status=RelocationRequest.STATUS_PENDING
    ).select_related('driver', 'from_zone', 'to_zone')
    return Response(RelocationRequestSerializer(relocations, many=True).data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def ministry_decide_relocation(request, relocation_id):
    """Ministry approves or rejects a relocation request."""
    try:
        relocation = RelocationRequest.objects.get(pk=relocation_id)
    except RelocationRequest.DoesNotExist:
        return Response({'error': 'Relocation request not found.'}, status=404)

    if relocation.status != RelocationRequest.STATUS_PENDING:
        return Response({'error': 'This request has already been decided.'}, status=400)

    serializer = RelocationDecisionSerializer(data=request.data)
    if not serializer.is_valid():
        return Response(serializer.errors, status=400)

    action = serializer.validated_data['action']

    if action == 'approve':
        valid_hours = serializer.validated_data.get('valid_hours', 4)
        relocation.approve(admin_user=request.user, valid_hours=valid_hours)

        from realtime.push import push_relocation_decision
        push_relocation_decision(relocation)

        return Response({
            'message': f'Relocation approved for {valid_hours} hours.',
            'valid_until': relocation.valid_until,
        })
    else:
        reason = serializer.validated_data.get('rejection_reason', '')
        relocation.reject(admin_user=request.user, reason=reason)

        from realtime.push import push_relocation_decision
        push_relocation_decision(relocation)

        return Response({'message': 'Relocation request rejected.'})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def ministry_compliance_report(request):
    """Compliance report: violations and scores per driver/route."""
    drivers = Driver.objects.select_related(
        'user', 'assigned_route'
    ).prefetch_related('violations').all()

    report = []
    for driver in drivers:
        violations = driver.violations.all()
        report.append({
            'license_plate':        driver.license_plate,
            'username':             driver.user.username,
            'assigned_route':       driver.assigned_route.name if driver.assigned_route else None,
            'compliance_score':     driver.compliance_score,
            'total_violations':     violations.count(),
            'open_violations':      violations.filter(status=RouteViolation.STATUS_OPEN).count(),
            'confirmed_violations': violations.filter(status=RouteViolation.STATUS_CONFIRMED).count(),
            'status':               driver.status,
        })

    report.sort(key=lambda x: x['compliance_score'])
    return Response(report)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def ministry_dashboard(request):
    """Full system snapshot for the Ministry dashboard."""
    drivers     = Driver.objects.all()
    violations  = RouteViolation.objects.all()
    relocations = RelocationRequest.objects.all()

    driver_stats = {
        'total':      drivers.count(),
        'on_route':   drivers.filter(status=Driver.STATUS_ON_ROUTE).count(),
        'off_route':  drivers.filter(status=Driver.STATUS_OFF_ROUTE).count(),
        'relocating': drivers.filter(status=Driver.STATUS_RELOCATING).count(),
        'offline':    drivers.filter(status=Driver.STATUS_OFFLINE).count(),
    }

    violation_stats = {
        'total':      violations.count(),
        'open':       violations.filter(status=RouteViolation.STATUS_OPEN).count(),
        'dispatched': violations.filter(status=RouteViolation.STATUS_DISPATCHED).count(),
        'confirmed':  violations.filter(status=RouteViolation.STATUS_CONFIRMED).count(),
        'dismissed':  violations.filter(status=RouteViolation.STATUS_DISMISSED).count(),
    }

    relocation_stats = {
        'pending':  relocations.filter(status=RelocationRequest.STATUS_PENDING).count(),
        'approved': relocations.filter(status=RelocationRequest.STATUS_APPROVED).count(),
        'rejected': relocations.filter(status=RelocationRequest.STATUS_REJECTED).count(),
    }

    zones = Zone.objects.prefetch_related('thresholds').all()
    zone_summaries = []
    for zone in zones:
        zone_summaries.append({
            'id':        zone.id,
            'name':      zone.name,
            'status':    evaluate_zone(zone),
            'bus_count': len(buses_in_zone(zone)),
        })

    return Response({
        'drivers':     driver_stats,
        'violations':  violation_stats,
        'relocations': relocation_stats,
        'zones':       zone_summaries,
    })


# ---------------------------------------------------------------------------
# Ministry — Route & Driver management (web dashboard)
# ---------------------------------------------------------------------------

@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def ministry_routes(request):
    """List all routes or create a new one."""
    if not is_ministry(request.user):
        return Response({'error': 'Ministry admin only.'}, status=403)

    if request.method == 'GET':
        routes = Route.objects.select_related('zone', 'destination_zone').all()
        return Response(RouteSerializer(routes, many=True).data)

    # POST — create
    serializer = RouteSerializer(data=request.data)
    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data, status=201)
    return Response(serializer.errors, status=400)


@api_view(['PATCH', 'DELETE'])
@permission_classes([IsAuthenticated])
def ministry_route_detail(request, route_id):
    """Update or delete a specific route."""
    if not is_ministry(request.user):
        return Response({'error': 'Ministry admin only.'}, status=403)

    try:
        route = Route.objects.get(pk=route_id)
    except Route.DoesNotExist:
        return Response({'error': 'Route not found.'}, status=404)

    if request.method == 'DELETE':
        route.delete()
        return Response({'message': 'Route deleted.'}, status=204)

    # PATCH — update
    serializer = RouteSerializer(route, data=request.data, partial=True)
    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data)
    return Response(serializer.errors, status=400)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def ministry_drivers(request):
    """Full driver list with compliance scores and assigned routes."""
    if not is_ministry(request.user):
        return Response({'error': 'Ministry admin only.'}, status=403)

    drivers = Driver.objects.select_related(
        'user', 'assigned_route', 'assigned_route__zone'
    ).all()
    return Response(DriverSerializer(drivers, many=True).data)


@api_view(['PATCH'])
@permission_classes([IsAuthenticated])
def ministry_assign_route(request, driver_id):
    """Assign or reassign a driver to a route."""
    if not is_ministry(request.user):
        return Response({'error': 'Ministry admin only.'}, status=403)

    try:
        driver = Driver.objects.get(pk=driver_id)
    except Driver.DoesNotExist:
        return Response({'error': 'Driver not found.'}, status=404)

    route_id = request.data.get('route_id')
    if route_id:
        try:
            route = Route.objects.get(pk=route_id)
            driver.assigned_route = route
        except Route.DoesNotExist:
            return Response({'error': 'Route not found.'}, status=404)
    else:
        driver.assigned_route = None

    driver.save()
    return Response(DriverSerializer(driver).data)
