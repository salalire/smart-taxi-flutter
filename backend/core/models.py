"""
Core data models for the Ethiopian Public Minibus Monitoring System.

New in this version:
    - Auto-dispatch: system finds nearest inspector automatically on violation
    - PassengerDemandReport: passengers report demand/supply conditions at stops
    - StopCheckIn: passengers check in at a stop to signal waiting demand
    - InspectorFieldObservation: inspectors file field observations beyond violations
    - Demand signal weighting by reporter GPS proximity
"""

from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone
import math


def _haversine_km(lat1, lon1, lat2, lon2):
    R = 6371
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(lat1))
         * math.cos(math.radians(lat2))
         * math.sin(dlon / 2) ** 2)
    return R * 2 * math.asin(math.sqrt(a))


# ---------------------------------------------------------------------------
# User
# ---------------------------------------------------------------------------

class User(AbstractUser):
    ROLE_DRIVER         = 'driver'
    ROLE_PASSENGER      = 'passenger'
    ROLE_INSPECTOR      = 'inspector'
    ROLE_MINISTRY_ADMIN = 'ministry_admin'
    ROLE_CHOICES = [
        (ROLE_DRIVER,         'Driver'),
        (ROLE_PASSENGER,      'Passenger'),
        (ROLE_INSPECTOR,      'Inspector'),
        (ROLE_MINISTRY_ADMIN, 'Ministry Admin'),
    ]
    role  = models.CharField(max_length=20, choices=ROLE_CHOICES)
    phone = models.CharField(max_length=20, unique=True)
    email = models.EmailField(unique=True)
    REQUIRED_FIELDS = ['email', 'phone', 'role']

    def __str__(self):
        return f'{self.username} ({self.role})'


# ---------------------------------------------------------------------------
# Zone
# ---------------------------------------------------------------------------

class Zone(models.Model):
    name             = models.CharField(max_length=100, unique=True)
    center_latitude  = models.FloatField()
    center_longitude = models.FloatField()
    radius_km        = models.FloatField(default=2.0)

    def __str__(self):
        return self.name


class ZoneThreshold(models.Model):
    DAY_CHOICES = [
        (0, 'Monday'), (1, 'Tuesday'), (2, 'Wednesday'),
        (3, 'Thursday'), (4, 'Friday'), (5, 'Saturday'), (6, 'Sunday'),
    ]
    zone        = models.ForeignKey(Zone, on_delete=models.CASCADE, related_name='thresholds')
    day_of_week = models.IntegerField(choices=DAY_CHOICES)
    hour_start  = models.IntegerField()
    hour_end    = models.IntegerField()
    min_buses   = models.IntegerField()
    max_buses   = models.IntegerField()

    class Meta:
        unique_together = ('zone', 'day_of_week', 'hour_start')
        ordering        = ['zone', 'day_of_week', 'hour_start']

    def __str__(self):
        day = dict(self.DAY_CHOICES).get(self.day_of_week, '?')
        return f'{self.zone.name} | {day} {self.hour_start:02d}:00-{self.hour_end:02d}:00 [{self.min_buses}-{self.max_buses}]'


# ---------------------------------------------------------------------------
# Route
# ---------------------------------------------------------------------------

class Route(models.Model):
    name             = models.CharField(max_length=200, unique=True)
    zone             = models.ForeignKey(Zone, on_delete=models.CASCADE, related_name='routes',
                                         help_text='Origin zone where the route starts.')
    destination_zone = models.ForeignKey(Zone, on_delete=models.SET_NULL, null=True, blank=True,
                                         related_name='destination_routes',
                                         help_text='Destination zone where the route ends.')
    official_fare    = models.DecimalField(max_digits=8, decimal_places=2)
    max_deviation_km = models.FloatField(default=0.3)
    is_active        = models.BooleanField(default=True)

    def __str__(self):
        return self.name

    def nearest_waypoint_distance(self, lat, lng):
        waypoints = self.waypoints.all()
        if not waypoints.exists():
            return 0.0
        return min(
            _haversine_km(lat, lng, wp.latitude, wp.longitude)
            for wp in waypoints
        )

    def is_position_on_route(self, lat, lng):
        return self.nearest_waypoint_distance(lat, lng) <= self.max_deviation_km


class RouteWaypoint(models.Model):
    route     = models.ForeignKey(Route, on_delete=models.CASCADE, related_name='waypoints')
    order     = models.PositiveIntegerField()
    latitude  = models.FloatField()
    longitude = models.FloatField()
    label     = models.CharField(max_length=100, blank=True)

    class Meta:
        ordering        = ['route', 'order']
        unique_together = ('route', 'order')

    def __str__(self):
        return f'{self.route.name} - point {self.order} ({self.label or "unnamed"})'


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

class Driver(models.Model):
    STATUS_ON_ROUTE   = 'on_route'
    STATUS_OFF_ROUTE  = 'off_route'
    STATUS_RELOCATING = 'relocating'
    STATUS_OFFLINE    = 'offline'
    STATUS_CHOICES = [
        (STATUS_ON_ROUTE,   'On Route'),
        (STATUS_OFF_ROUTE,  'Off Route'),
        (STATUS_RELOCATING, 'Relocating'),
        (STATUS_OFFLINE,    'Offline'),
    ]

    user              = models.OneToOneField(User, on_delete=models.CASCADE, related_name='driver_profile')
    assigned_route    = models.ForeignKey(Route, null=True, blank=True, on_delete=models.SET_NULL, related_name='drivers')
    license_plate     = models.CharField(max_length=20, unique=True)
    status            = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_OFFLINE)
    compliance_score  = models.IntegerField(default=100)
    current_latitude  = models.FloatField(null=True, blank=True)
    current_longitude = models.FloatField(null=True, blank=True)
    last_seen         = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f'{self.license_plate} - {self.user.username} [{self.status}]'

    def update_location(self, latitude, longitude):
        self.current_latitude  = latitude
        self.current_longitude = longitude
        self.last_seen         = timezone.now()

        on_route = True
        if self.assigned_route:
            on_route = self.assigned_route.is_position_on_route(latitude, longitude)

        if self.status not in (self.STATUS_RELOCATING, self.STATUS_OFFLINE):
            self.status = self.STATUS_ON_ROUTE if on_route else self.STATUS_OFF_ROUTE

        self.save(update_fields=['current_latitude', 'current_longitude', 'last_seen', 'status'])

        location_update = LocationUpdate.objects.create(
            driver=self,
            latitude=latitude,
            longitude=longitude,
            is_on_route=on_route,
        )

        if not on_route and self.status != self.STATUS_RELOCATING:
            self._handle_off_route(latitude, longitude)

        return location_update

    def _handle_off_route(self, latitude, longitude):
        """
        Create a RouteViolation and auto-dispatch the nearest available inspector.
        No Ministry action required — the system handles it immediately.
        """
        already_open = RouteViolation.objects.filter(
            driver=self,
            status=RouteViolation.STATUS_OPEN,
        ).exists()

        if not already_open:
            violation = RouteViolation.objects.create(
                driver=self,
                route=self.assigned_route,
                latitude=latitude,
                longitude=longitude,
            )
            # Auto-dispatch nearest inspector (Idea 1)
            _auto_dispatch_inspector(violation)

    def deduct_compliance(self, points=5):
        self.compliance_score = max(0, self.compliance_score - points)
        self.save(update_fields=['compliance_score'])

    def restore_compliance(self, points=2):
        self.compliance_score = min(100, self.compliance_score + points)
        self.save(update_fields=['compliance_score'])


def _auto_dispatch_inspector(violation):
    """
    System automatically finds the best available inspector
    and dispatches them instantly.

    Priority:
    1. Inspector assigned to the violation's zone with GPS coordinates
    2. Nearest inspector with GPS coordinates
    3. Inspector assigned to the zone (no GPS)
    4. Any available inspector
    """
    from core.models import Inspector, InspectorDispatch

    # Already has a pending dispatch — don't duplicate
    already_dispatched = InspectorDispatch.objects.filter(
        violation=violation,
        status__in=[InspectorDispatch.STATUS_SENT, InspectorDispatch.STATUS_ACKNOWLEDGED]
    ).exists()
    if already_dispatched:
        return

    zone = violation.route.zone if violation.route else None

    # Priority 1: Inspector assigned to this zone with GPS
    if zone:
        zone_inspectors = Inspector.objects.filter(
            assigned_zone=zone,
            current_latitude__isnull=False,
            current_longitude__isnull=False,
            is_available=True,
        )
        if zone_inspectors.exists():
            nearest = _find_nearest_inspector(zone_inspectors, violation)
            if nearest:
                _create_dispatch(nearest, violation)
                return

    # Priority 2: Any inspector with GPS, nearest to violation
    all_inspectors = Inspector.objects.filter(
        current_latitude__isnull=False,
        current_longitude__isnull=False,
        is_available=True,
    )
    if all_inspectors.exists():
        nearest = _find_nearest_inspector(all_inspectors, violation)
        if nearest:
            _create_dispatch(nearest, violation)
            return

    # Priority 3: Inspector assigned to zone (no GPS)
    if zone:
        zone_inspector = Inspector.objects.filter(
            assigned_zone=zone, is_available=True
        ).first()
        if zone_inspector:
            _create_dispatch(zone_inspector, violation)
            return

    # Priority 4: Any available inspector
    any_inspector = Inspector.objects.filter(is_available=True).first()
    if any_inspector:
        _create_dispatch(any_inspector, violation)


def _find_nearest_inspector(inspectors, violation):
    nearest      = None
    nearest_dist = float('inf')
    for inspector in inspectors:
        if inspector.current_latitude and inspector.current_longitude:
            dist = _haversine_km(
                violation.latitude, violation.longitude,
                inspector.current_latitude, inspector.current_longitude,
            )
            if dist < nearest_dist:
                nearest_dist = dist
                nearest      = inspector
    return nearest


def _create_dispatch(inspector, violation):
    from core.models import InspectorDispatch
    dispatch = InspectorDispatch.objects.create(
        inspector=inspector,
        violation=violation,
        auto_dispatched=True,
    )
    try:
        from realtime.push import push_dispatch_to_inspector
        push_dispatch_to_inspector(inspector, dispatch)
    except Exception:
        pass
    try:
        from realtime.push import push_violation_to_dashboard
        push_violation_to_dashboard(violation)
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Inspector
# ---------------------------------------------------------------------------

class Inspector(models.Model):
    user              = models.OneToOneField(User, on_delete=models.CASCADE, related_name='inspector_profile')
    badge_number      = models.CharField(max_length=50, unique=True)
    assigned_zone     = models.ForeignKey(Zone, null=True, blank=True, on_delete=models.SET_NULL, related_name='inspectors')
    current_latitude  = models.FloatField(null=True, blank=True)
    current_longitude = models.FloatField(null=True, blank=True)
    is_available      = models.BooleanField(default=True)  # False when already handling a dispatch

    def __str__(self):
        return f'Inspector {self.badge_number} - {self.user.username}'


# ---------------------------------------------------------------------------
# Passenger
# ---------------------------------------------------------------------------

class Passenger(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='passenger_profile')

    def __str__(self):
        return f'Passenger: {self.user.username}'


# ---------------------------------------------------------------------------
# LocationUpdate
# ---------------------------------------------------------------------------

class LocationUpdate(models.Model):
    driver      = models.ForeignKey(Driver, on_delete=models.CASCADE, related_name='location_updates')
    latitude    = models.FloatField()
    longitude   = models.FloatField()
    timestamp   = models.DateTimeField(auto_now_add=True)
    is_on_route = models.BooleanField(default=True)

    class Meta:
        ordering = ['-timestamp']

    def __str__(self):
        status = 'ON ROUTE' if self.is_on_route else 'OFF ROUTE'
        return f'{self.driver.license_plate} @ ({self.latitude:.4f}, {self.longitude:.4f}) [{status}]'


# ---------------------------------------------------------------------------
# RouteViolation
# ---------------------------------------------------------------------------

class RouteViolation(models.Model):
    STATUS_OPEN        = 'open'
    STATUS_DISPATCHED  = 'inspector_dispatched'
    STATUS_CONFIRMED   = 'confirmed'
    STATUS_DISMISSED   = 'dismissed'
    STATUS_CHOICES = [
        (STATUS_OPEN,       'Open'),
        (STATUS_DISPATCHED, 'Inspector Dispatched'),
        (STATUS_CONFIRMED,  'Confirmed'),
        (STATUS_DISMISSED,  'Dismissed'),
    ]

    driver      = models.ForeignKey(Driver, on_delete=models.CASCADE, related_name='violations')
    route       = models.ForeignKey(Route, null=True, blank=True, on_delete=models.SET_NULL, related_name='violations')
    detected_at = models.DateTimeField(auto_now_add=True)
    latitude    = models.FloatField()
    longitude   = models.FloatField()
    status      = models.CharField(max_length=30, choices=STATUS_CHOICES, default=STATUS_OPEN)
    recorded_by = models.ForeignKey(
        Inspector, null=True, blank=True,
        on_delete=models.SET_NULL, related_name='recorded_violations'
    )
    notes = models.TextField(blank=True)

    class Meta:
        ordering = ['-detected_at']

    def __str__(self):
        return f'Violation #{self.pk} - {self.driver.license_plate} [{self.status}]'

    def confirm(self, inspector, notes=''):
        self.status      = self.STATUS_CONFIRMED
        self.recorded_by = inspector
        self.notes       = notes
        self.save(update_fields=['status', 'recorded_by', 'notes'])
        self.driver.deduct_compliance(points=8)
        # Free up inspector
        inspector.is_available = True
        inspector.save(update_fields=['is_available'])

    def dismiss(self, inspector, notes=''):
        self.status      = self.STATUS_DISMISSED
        self.recorded_by = inspector
        self.notes       = notes
        self.save(update_fields=['status', 'recorded_by', 'notes'])
        inspector.is_available = True
        inspector.save(update_fields=['is_available'])


# ---------------------------------------------------------------------------
# PassengerReport  (violation reports — wrong route, overcharging, etc.)
# ---------------------------------------------------------------------------

class PassengerReport(models.Model):
    TYPE_WRONG_ROUTE  = 'wrong_route'
    TYPE_OVERCHARGING = 'overcharging'
    TYPE_OVERCROWDING = 'overcrowding'
    TYPE_OTHER        = 'other'
    TYPE_CHOICES = [
        (TYPE_WRONG_ROUTE,  'Wrong Route'),
        (TYPE_OVERCHARGING, 'Overcharging'),
        (TYPE_OVERCROWDING, 'Overcrowding'),
        (TYPE_OTHER,        'Other'),
    ]

    reporter          = models.ForeignKey(Passenger, on_delete=models.CASCADE, related_name='reports')
    plate_number      = models.CharField(max_length=20)
    report_type       = models.CharField(max_length=20, choices=TYPE_CHOICES)
    zone              = models.ForeignKey(Zone, null=True, blank=True, on_delete=models.SET_NULL)
    description       = models.TextField(blank=True)
    reporter_latitude  = models.FloatField(null=True, blank=True)
    reporter_longitude = models.FloatField(null=True, blank=True)
    created_at        = models.DateTimeField(auto_now_add=True)
    is_reviewed       = models.BooleanField(default=False)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'Report by {self.reporter.user.username} - plate {self.plate_number} [{self.report_type}]'


# ---------------------------------------------------------------------------
# PassengerDemandReport  (Idea 2 + 3: passengers report demand/supply conditions)
# ---------------------------------------------------------------------------

class PassengerDemandReport(models.Model):
    """
    A passenger reports the demand or supply situation they observe at a stop.

    DEMAND reports: "There are many people waiting here and no bus is coming."
    SUPPLY reports: "There are many empty buses here with no passengers."

    These reports feed directly into zone evaluation alongside GPS data.
    Reports are weighted by how close the reporter is to the zone center (Idea 6).
    """
    TYPE_HIGH_DEMAND    = 'high_demand'     # Many passengers waiting, no buses
    TYPE_LOW_DEMAND     = 'low_demand'      # Very few passengers, buses are empty
    TYPE_OVERSUPPLY     = 'oversupply'      # Too many buses, not enough passengers
    TYPE_LONG_WAIT      = 'long_wait'       # Waiting more than 20 minutes
    TYPE_STOP_ABANDONED = 'stop_abandoned'  # Bus stop has been completely abandoned
    TYPE_CHOICES = [
        (TYPE_HIGH_DEMAND,    'High Demand - Many passengers waiting'),
        (TYPE_LOW_DEMAND,     'Low Demand - Very few passengers'),
        (TYPE_OVERSUPPLY,     'Oversupply - Too many empty buses'),
        (TYPE_LONG_WAIT,      'Long Wait - No bus for 20+ minutes'),
        (TYPE_STOP_ABANDONED, 'Stop Abandoned - No service at all'),
    ]

    reporter           = models.ForeignKey(Passenger, on_delete=models.CASCADE, related_name='demand_reports')
    zone               = models.ForeignKey(Zone, on_delete=models.CASCADE, related_name='demand_reports')
    report_type        = models.CharField(max_length=20, choices=TYPE_CHOICES)
    description        = models.TextField(blank=True)
    reporter_latitude  = models.FloatField()
    reporter_longitude = models.FloatField()
    # Weight 0.0-1.0: how reliable this report is based on reporter proximity to zone
    # Computed automatically at save time (Idea 6)
    weight             = models.FloatField(default=1.0)
    created_at         = models.DateTimeField(auto_now_add=True)
    is_processed       = models.BooleanField(default=False)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'DemandReport by {self.reporter.user.username} - {self.zone.name} [{self.report_type}]'

    def save(self, *args, **kwargs):
        # Idea 6: compute weight based on reporter distance to zone center
        # Reporter at zone center = weight 1.0
        # Reporter 2x zone radius away = weight 0.1 (barely counts)
        dist = _haversine_km(
            self.reporter_latitude, self.reporter_longitude,
            self.zone.center_latitude, self.zone.center_longitude,
        )
        max_trusted_dist = self.zone.radius_km * 1.5
        if dist <= self.zone.radius_km:
            self.weight = 1.0           # Inside zone — fully trusted
        elif dist <= max_trusted_dist:
            # Linearly decrease from 1.0 to 0.3 as distance increases
            ratio = (dist - self.zone.radius_km) / (max_trusted_dist - self.zone.radius_km)
            self.weight = round(1.0 - (0.7 * ratio), 2)
        else:
            self.weight = 0.1           # Far away — barely counts
        super().save(*args, **kwargs)


# ---------------------------------------------------------------------------
# StopCheckIn  (Idea 4: passive demand signal — passenger taps "I am waiting")
# ---------------------------------------------------------------------------

class StopCheckIn(models.Model):
    """
    A passenger checks in at a bus stop to signal they are waiting.
    No description needed — just one tap.
    The system counts active check-ins per zone to measure real-time demand.

    A check-in expires after 30 minutes automatically.
    If a bus arrives and the passenger boards, they can check out early.
    """
    passenger          = models.ForeignKey(Passenger, on_delete=models.CASCADE, related_name='checkins')
    zone               = models.ForeignKey(Zone, on_delete=models.CASCADE, related_name='checkins')
    latitude           = models.FloatField()
    longitude          = models.FloatField()
    checked_in_at      = models.DateTimeField(auto_now_add=True)
    checked_out_at     = models.DateTimeField(null=True, blank=True)
    is_active          = models.BooleanField(default=True)
    # Weight based on proximity (same logic as PassengerDemandReport)
    weight             = models.FloatField(default=1.0)

    class Meta:
        ordering = ['-checked_in_at']

    def __str__(self):
        status = 'waiting' if self.is_active else 'done'
        return f'{self.passenger.user.username} at {self.zone.name} [{status}]'

    def save(self, *args, **kwargs):
        dist = _haversine_km(
            self.latitude, self.longitude,
            self.zone.center_latitude, self.zone.center_longitude,
        )
        self.weight = 1.0 if dist <= self.zone.radius_km else 0.5
        super().save(*args, **kwargs)

    def checkout(self):
        """Passenger boarded a bus — check out."""
        self.is_active      = False
        self.checked_out_at = timezone.now()
        self.save(update_fields=['is_active', 'checked_out_at'])

    @classmethod
    def expire_old_checkins(cls):
        """Mark check-ins older than 30 minutes as inactive."""
        cutoff = timezone.now() - timezone.timedelta(minutes=30)
        cls.objects.filter(is_active=True, checked_in_at__lt=cutoff).update(
            is_active=False,
            checked_out_at=timezone.now(),
        )


# ---------------------------------------------------------------------------
# InspectorFieldObservation  (Idea 5: inspector files field observations)
# ---------------------------------------------------------------------------

class InspectorFieldObservation(models.Model):
    """
    An inspector files a field observation beyond just violations.
    These are qualitative ground-truth reports that enrich the system's data.

    Examples:
    - "Bus AA-12345 is on route but not stopping to pick passengers"
    - "Stop at Megenagna has been abandoned for 1 hour"
    - "Driver turned off GPS but is still operating"
    - "Overcrowding at Bole terminal — 40+ people waiting"
    """
    TYPE_BUS_NOT_STOPPING   = 'bus_not_stopping'
    TYPE_STOP_ABANDONED     = 'stop_abandoned'
    TYPE_GPS_DISABLED       = 'gps_disabled'
    TYPE_OVERCROWDING       = 'overcrowding'
    TYPE_UNDERCROWDING      = 'undercrowding'
    TYPE_FARE_VIOLATION     = 'fare_violation'
    TYPE_OTHER              = 'other'
    TYPE_CHOICES = [
        (TYPE_BUS_NOT_STOPPING, 'Bus on route but not stopping'),
        (TYPE_STOP_ABANDONED,   'Bus stop abandoned'),
        (TYPE_GPS_DISABLED,     'Driver GPS disabled'),
        (TYPE_OVERCROWDING,     'Overcrowding at stop'),
        (TYPE_UNDERCROWDING,    'Very low demand at stop'),
        (TYPE_FARE_VIOLATION,   'Fare violation observed'),
        (TYPE_OTHER,            'Other observation'),
    ]

    inspector         = models.ForeignKey(Inspector, on_delete=models.CASCADE, related_name='field_observations')
    zone              = models.ForeignKey(Zone, on_delete=models.CASCADE, related_name='field_observations')
    observation_type  = models.CharField(max_length=30, choices=TYPE_CHOICES)
    plate_number      = models.CharField(max_length=20, blank=True)  # Optional — may not involve a specific bus
    latitude          = models.FloatField()
    longitude         = models.FloatField()
    description       = models.TextField()
    created_at        = models.DateTimeField(auto_now_add=True)
    is_reviewed       = models.BooleanField(default=False)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'Observation by {self.inspector.badge_number} - {self.zone.name} [{self.observation_type}]'


# ---------------------------------------------------------------------------
# RelocationRequest
# ---------------------------------------------------------------------------

class RelocationRequest(models.Model):
    STATUS_PENDING  = 'pending'
    STATUS_APPROVED = 'approved'
    STATUS_REJECTED = 'rejected'
    STATUS_EXPIRED  = 'expired'
    STATUS_CHOICES = [
        (STATUS_PENDING,  'Pending'),
        (STATUS_APPROVED, 'Approved'),
        (STATUS_REJECTED, 'Rejected'),
        (STATUS_EXPIRED,  'Expired'),
    ]

    INITIATED_SYSTEM  = 'system'
    INITIATED_DRIVER  = 'driver'
    INITIATED_CHOICES = [
        (INITIATED_SYSTEM, 'System Generated'),
        (INITIATED_DRIVER, 'Driver Requested'),
    ]

    driver           = models.ForeignKey(Driver, on_delete=models.CASCADE, related_name='relocation_requests')
    from_zone        = models.ForeignKey(Zone, on_delete=models.CASCADE, related_name='relocations_from')
    to_zone          = models.ForeignKey(Zone, on_delete=models.CASCADE, related_name='relocations_to')
    reason           = models.TextField()
    initiated_by     = models.CharField(max_length=10, choices=INITIATED_CHOICES, default=INITIATED_SYSTEM)
    status           = models.CharField(max_length=10, choices=STATUS_CHOICES, default=STATUS_PENDING)
    requested_at     = models.DateTimeField(auto_now_add=True)
    decided_at       = models.DateTimeField(null=True, blank=True)
    valid_until      = models.DateTimeField(null=True, blank=True)
    approved_by      = models.ForeignKey(
        User, null=True, blank=True,
        on_delete=models.SET_NULL, related_name='approved_relocations'
    )
    rejection_reason = models.TextField(blank=True)

    class Meta:
        ordering = ['-requested_at']

    def __str__(self):
        return f'Relocation #{self.pk} - {self.driver.license_plate} to {self.to_zone.name} [{self.status}]'

    def approve(self, admin_user, valid_hours=4):
        self.status      = self.STATUS_APPROVED
        self.decided_at  = timezone.now()
        self.valid_until = timezone.now() + timezone.timedelta(hours=valid_hours)
        self.approved_by = admin_user
        self.save(update_fields=['status', 'decided_at', 'valid_until', 'approved_by'])
        self.driver.status = Driver.STATUS_RELOCATING
        self.driver.save(update_fields=['status'])

    def reject(self, admin_user, reason=''):
        self.status           = self.STATUS_REJECTED
        self.decided_at       = timezone.now()
        self.approved_by      = admin_user
        self.rejection_reason = reason
        self.save(update_fields=['status', 'decided_at', 'approved_by', 'rejection_reason'])

    def is_valid(self):
        if self.status != self.STATUS_APPROVED:
            return False
        if self.valid_until and timezone.now() > self.valid_until:
            return False
        return True


# ---------------------------------------------------------------------------
# InspectorDispatch
# ---------------------------------------------------------------------------

class InspectorDispatch(models.Model):
    STATUS_SENT         = 'sent'
    STATUS_ACKNOWLEDGED = 'acknowledged'
    STATUS_COMPLETED    = 'completed'
    STATUS_CHOICES = [
        (STATUS_SENT,         'Sent'),
        (STATUS_ACKNOWLEDGED, 'Acknowledged'),
        (STATUS_COMPLETED,    'Completed'),
    ]

    inspector       = models.ForeignKey(Inspector, on_delete=models.CASCADE, related_name='dispatches')
    violation       = models.ForeignKey(RouteViolation, on_delete=models.CASCADE, related_name='dispatches')
    dispatched_at   = models.DateTimeField(auto_now_add=True)
    responded_at    = models.DateTimeField(null=True, blank=True)
    status          = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_SENT)
    auto_dispatched = models.BooleanField(default=False)  # True = system dispatched, False = Ministry dispatched

    class Meta:
        ordering = ['-dispatched_at']

    def __str__(self):
        source = 'AUTO' if self.auto_dispatched else 'MANUAL'
        return f'Dispatch #{self.pk} [{source}] to Inspector {self.inspector.badge_number} [{self.status}]'

    def acknowledge(self):
        self.status       = self.STATUS_ACKNOWLEDGED
        self.responded_at = timezone.now()
        self.save(update_fields=['status', 'responded_at'])
        self.violation.status = RouteViolation.STATUS_DISPATCHED
        self.violation.save(update_fields=['status'])
        # Mark inspector as busy
        self.inspector.is_available = False
        self.inspector.save(update_fields=['is_available'])

    def complete(self):
        self.status       = self.STATUS_COMPLETED
        self.responded_at = timezone.now()
        self.save(update_fields=['status', 'responded_at'])
        # Free up inspector
        self.inspector.is_available = True
        self.inspector.save(update_fields=['is_available'])
