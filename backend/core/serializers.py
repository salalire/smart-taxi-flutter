"""
Serializers for the core app.
"""

from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .models import (
    User, Driver, Inspector, Passenger,
    Zone, ZoneThreshold, Route, RouteWaypoint,
    LocationUpdate, RouteViolation, PassengerReport, PassengerDemandReport,
    StopCheckIn, InspectorFieldObservation,
    RelocationRequest, InspectorDispatch,
)


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

class RegisterSerializer(serializers.ModelSerializer):
    password  = serializers.CharField(write_only=True, required=True, validators=[validate_password])
    password2 = serializers.CharField(write_only=True, required=True, label='Confirm password')

    # Driver-only fields
    license_plate  = serializers.CharField(required=False, allow_blank=True)
    assigned_route = serializers.PrimaryKeyRelatedField(
        queryset=Route.objects.all(), required=False, allow_null=True
    )

    # Inspector-only fields
    badge_number  = serializers.CharField(required=False, allow_blank=True)
    assigned_zone = serializers.PrimaryKeyRelatedField(
        queryset=Zone.objects.all(), required=False, allow_null=True
    )

    class Meta:
        model  = User
        fields = [
            'username', 'email', 'phone', 'role',
            'password', 'password2',
            'license_plate', 'assigned_route',
            'badge_number', 'assigned_zone',
        ]

    def validate(self, attrs):
        if attrs['password'] != attrs['password2']:
            raise serializers.ValidationError({'password': 'Passwords do not match.'})

        role = attrs.get('role')
        if role == User.ROLE_DRIVER and not attrs.get('license_plate'):
            raise serializers.ValidationError({'license_plate': 'License plate is required for drivers.'})
        if role == User.ROLE_INSPECTOR and not attrs.get('badge_number'):
            raise serializers.ValidationError({'badge_number': 'Badge number is required for inspectors.'})
        if role == User.ROLE_MINISTRY_ADMIN:
            raise serializers.ValidationError({'role': 'Ministry admin accounts are created by system administrators only.'})

        return attrs

    def create(self, validated_data):
        validated_data.pop('password2')
        password       = validated_data.pop('password')
        license_plate  = validated_data.pop('license_plate', None)
        assigned_route = validated_data.pop('assigned_route', None)
        badge_number   = validated_data.pop('badge_number', None)
        assigned_zone  = validated_data.pop('assigned_zone', None)

        user = User(**validated_data)
        user.set_password(password)
        user.save()

        if user.role == User.ROLE_DRIVER:
            Driver.objects.create(
                user=user,
                license_plate=license_plate,
                assigned_route=assigned_route,
            )
        elif user.role == User.ROLE_PASSENGER:
            Passenger.objects.create(user=user)
        elif user.role == User.ROLE_INSPECTOR:
            Inspector.objects.create(
                user=user,
                badge_number=badge_number,
                assigned_zone=assigned_zone,
            )

        return user


class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    """Embeds role, username, user_id into the JWT payload."""

    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        token['role']     = user.role
        token['username'] = user.username
        return token

    def validate(self, attrs):
        data = super().validate(attrs)
        data['role']     = self.user.role
        data['username'] = self.user.username
        data['user_id']  = self.user.id
        return data


# ---------------------------------------------------------------------------
# Zone & Route
# ---------------------------------------------------------------------------

class ZoneThresholdSerializer(serializers.ModelSerializer):
    class Meta:
        model  = ZoneThreshold
        fields = ['id', 'day_of_week', 'hour_start', 'hour_end', 'min_buses', 'max_buses']


class ZoneSerializer(serializers.ModelSerializer):
    thresholds   = ZoneThresholdSerializer(many=True, read_only=True)
    bus_count    = serializers.IntegerField(read_only=True, default=0)
    demand_count = serializers.IntegerField(read_only=True, default=0)
    status       = serializers.CharField(read_only=True, default='OK')

    class Meta:
        model  = Zone
        fields = ['id', 'name', 'center_latitude', 'center_longitude',
                  'radius_km', 'thresholds', 'bus_count', 'demand_count', 'status']


class RouteWaypointSerializer(serializers.ModelSerializer):
    class Meta:
        model  = RouteWaypoint
        fields = ['id', 'order', 'latitude', 'longitude', 'label']


class RouteSerializer(serializers.ModelSerializer):
    waypoints             = RouteWaypointSerializer(many=True, read_only=True)
    zone_name             = serializers.CharField(source='zone.name', read_only=True)
    destination_zone_id   = serializers.IntegerField(source='destination_zone.id', read_only=True, default=None)
    destination_zone_name = serializers.CharField(source='destination_zone.name', read_only=True, default=None)

    class Meta:
        model  = Route
        fields = ['id', 'name', 'zone', 'zone_name', 'official_fare',
                  'max_deviation_km', 'is_active', 'waypoints',
                  'destination_zone', 'destination_zone_id', 'destination_zone_name']
        extra_kwargs = {
            'destination_zone': {'write_only': True, 'required': False, 'allow_null': True},
        }


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

class DriverSerializer(serializers.ModelSerializer):
    username         = serializers.CharField(source='user.username', read_only=True)
    assigned_route   = RouteSerializer(read_only=True)

    class Meta:
        model  = Driver
        fields = [
            'id', 'username', 'license_plate', 'status',
            'compliance_score', 'assigned_route',
            'current_latitude', 'current_longitude', 'last_seen',
        ]


class DriverStatusSerializer(serializers.ModelSerializer):
    class Meta:
        model  = Driver
        fields = ['status']

    def validate_status(self, value):
        allowed = [Driver.STATUS_ON_ROUTE, Driver.STATUS_OFFLINE]
        if value not in allowed:
            raise serializers.ValidationError(
                f'Drivers can only self-report: {allowed}. '
                f'off_route and relocating are set by the system.'
            )
        return value


# ---------------------------------------------------------------------------
# Inspector
# ---------------------------------------------------------------------------

class InspectorSerializer(serializers.ModelSerializer):
    username      = serializers.CharField(source='user.username', read_only=True)
    assigned_zone = ZoneSerializer(read_only=True)

    class Meta:
        model  = Inspector
        fields = ['id', 'username', 'badge_number', 'assigned_zone',
                  'current_latitude', 'current_longitude']


# ---------------------------------------------------------------------------
# LocationUpdate
# ---------------------------------------------------------------------------

class LocationUpdateSerializer(serializers.ModelSerializer):
    class Meta:
        model  = LocationUpdate
        fields = ['id', 'latitude', 'longitude', 'timestamp', 'is_on_route']


# ---------------------------------------------------------------------------
# RouteViolation
# ---------------------------------------------------------------------------

class RouteViolationSerializer(serializers.ModelSerializer):
    driver_plate  = serializers.CharField(source='driver.license_plate', read_only=True)
    route_name    = serializers.CharField(source='route.name', read_only=True)
    inspector_badge = serializers.CharField(source='recorded_by.badge_number', read_only=True, allow_null=True, default=None)

    class Meta:
        model  = RouteViolation
        fields = [
            'id', 'driver_plate', 'route_name', 'detected_at',
            'latitude', 'longitude', 'status', 'inspector_badge', 'notes',
        ]


class ViolationRecordSerializer(serializers.Serializer):
    """Used by inspector to record a violation on the spot."""
    plate_number = serializers.CharField()
    notes        = serializers.CharField(required=False, allow_blank=True)
    action       = serializers.ChoiceField(choices=['confirm', 'dismiss'])


# ---------------------------------------------------------------------------
# PassengerReport
# ---------------------------------------------------------------------------

class PassengerReportSerializer(serializers.ModelSerializer):
    passenger_username = serializers.CharField(source='reporter.user.username', read_only=True)
    zone_name          = serializers.CharField(source='zone.name', read_only=True, default=None)

    class Meta:
        model  = PassengerReport
        fields = ['id', 'passenger_username', 'plate_number', 'report_type',
                  'zone', 'zone_name', 'description', 'reporter_latitude', 'reporter_longitude',
                  'created_at', 'is_reviewed']
        read_only_fields = ['created_at', 'is_reviewed']


class PassengerDemandReportSerializer(serializers.ModelSerializer):
    zone_name        = serializers.CharField(source='zone.name', read_only=True)
    reporter_username = serializers.CharField(source='reporter.user.username', read_only=True)

    class Meta:
        model  = PassengerDemandReport
        fields = ['id', 'zone', 'zone_name', 'reporter_username', 'report_type', 'description',
                  'reporter_latitude', 'reporter_longitude', 'weight', 'created_at']
        read_only_fields = ['weight', 'created_at']


class StopCheckInSerializer(serializers.ModelSerializer):
    """
    Idea 4: One-tap check-in at a bus stop.
    Passenger provides their GPS and the zone they are waiting in.
    """
    zone_name = serializers.CharField(source='zone.name', read_only=True)

    class Meta:
        model  = StopCheckIn
        fields = ['id', 'zone', 'zone_name', 'latitude', 'longitude',
                  'checked_in_at', 'is_active', 'weight']
        read_only_fields = ['checked_in_at', 'is_active', 'weight']


class InspectorFieldObservationSerializer(serializers.ModelSerializer):
    """
    Idea 5: Inspector files a qualitative field observation.
    """
    inspector_badge = serializers.CharField(source='inspector.badge_number', read_only=True)
    zone_name       = serializers.CharField(source='zone.name', read_only=True)

    class Meta:
        model  = InspectorFieldObservation
        fields = ['id', 'inspector_badge', 'zone', 'zone_name', 'observation_type',
                  'plate_number', 'latitude', 'longitude', 'description',
                  'created_at', 'is_reviewed']
        read_only_fields = ['created_at', 'is_reviewed']


# ---------------------------------------------------------------------------
# RelocationRequest
# ---------------------------------------------------------------------------

class RelocationRequestSerializer(serializers.ModelSerializer):
    driver_plate  = serializers.CharField(source='driver.license_plate', read_only=True)
    from_zone_name = serializers.CharField(source='from_zone.name', read_only=True)
    to_zone_name   = serializers.CharField(source='to_zone.name',   read_only=True)
    approved_by_username = serializers.CharField(source='approved_by.username', read_only=True)

    class Meta:
        model  = RelocationRequest
        fields = [
            'id', 'driver_plate', 'from_zone_name', 'to_zone_name',
            'reason', 'initiated_by', 'status',
            'requested_at', 'decided_at', 'valid_until',
            'approved_by_username', 'rejection_reason',
        ]


class RelocationRequestCreateSerializer(serializers.ModelSerializer):
    """Used by driver to submit a relocation request."""
    class Meta:
        model  = RelocationRequest
        fields = ['to_zone', 'reason']


class RelocationDecisionSerializer(serializers.Serializer):
    """Used by Ministry Admin to approve or reject a relocation."""
    action           = serializers.ChoiceField(choices=['approve', 'reject'])
    valid_hours      = serializers.IntegerField(required=False, default=4, min_value=1, max_value=24)
    rejection_reason = serializers.CharField(required=False, allow_blank=True)


# ---------------------------------------------------------------------------
# InspectorDispatch
# ---------------------------------------------------------------------------

class InspectorDispatchSerializer(serializers.ModelSerializer):
    inspector_badge = serializers.CharField(source='inspector.badge_number', read_only=True)
    violation       = RouteViolationSerializer(read_only=True)

    class Meta:
        model  = InspectorDispatch
        fields = ['id', 'inspector_badge', 'violation', 'dispatched_at',
                  'responded_at', 'status', 'auto_dispatched']


class DispatchRespondSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=['acknowledge', 'complete'])


# ---------------------------------------------------------------------------
# Bus plate lookup (Inspector)
# ---------------------------------------------------------------------------

class BusLookupSerializer(serializers.ModelSerializer):
    """
    What an inspector sees when they scan a plate number.
    Full picture: current status, route, compliance score, recent violations.
    """
    username         = serializers.CharField(source='user.username', read_only=True)
    assigned_route   = serializers.CharField(source='assigned_route.name', read_only=True)
    recent_violations = RouteViolationSerializer(
        source='violations', many=True, read_only=True
    )
    active_relocation = serializers.SerializerMethodField()

    class Meta:
        model  = Driver
        fields = [
            'license_plate', 'username', 'status', 'compliance_score',
            'assigned_route', 'current_latitude', 'current_longitude',
            'recent_violations', 'active_relocation',
        ]

    def get_active_relocation(self, driver):
        relocation = RelocationRequest.objects.filter(
            driver=driver,
            status=RelocationRequest.STATUS_APPROVED,
        ).order_by('-requested_at').first()

        if relocation and relocation.is_valid():
            return {
                'to_zone':    relocation.to_zone.name,
                'valid_until': relocation.valid_until,
            }
        return None
