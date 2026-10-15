"""
Distribution and compliance logic.

Functions:
    haversine_km                 - GPS distance calculation
    buses_in_zone                - Count on-route buses inside a zone
    get_active_threshold         - Get the threshold for current day/hour
    weighted_demand_score        - Combined passenger demand signal score
    evaluate_zone                - Determine zone supply/demand status
    find_best_bus_for_zone       - Find nearest on-route bus for relocation
    run_distribution             - Main loop: detect imbalances, create relocation requests
    expire_old_relocations       - Mark expired relocation permits
    detect_offline_drivers       - Flag drivers with no GPS ping in 30+ minutes
    restore_weekly_compliance    - Weekly compliance score recovery for clean drivers
    broadcast_all_zone_statuses  - Push all zone statuses to dashboard
"""

import math
from django.utils import timezone


def haversine_km(lat1, lon1, lat2, lon2):
    """Straight-line distance between two GPS points in kilometers."""
    R = 6371
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(lat1))
         * math.cos(math.radians(lat2))
         * math.sin(dlon / 2) ** 2)
    return R * 2 * math.asin(math.sqrt(a))


def get_active_threshold(zone):
    """Return the ZoneThreshold matching the current day and hour."""
    now = timezone.localtime()
    return zone.thresholds.filter(
        day_of_week=now.weekday(),
        hour_start__lte=now.hour,
        hour_end__gt=now.hour,
    ).first()


def buses_in_zone(zone):
    """
    Return list of Driver objects currently on-route inside the zone's radius.
    Only on_route and relocating drivers count toward supply.
    Off-route and offline drivers do not count.
    """
    from core.models import Driver
    active = Driver.objects.filter(
        status__in=[Driver.STATUS_ON_ROUTE, Driver.STATUS_RELOCATING],
        current_latitude__isnull=False,
        current_longitude__isnull=False,
    ).select_related('user', 'assigned_route')

    return [
        d for d in active
        if haversine_km(
            d.current_latitude, d.current_longitude,
            zone.center_latitude, zone.center_longitude
        ) <= zone.radius_km
    ]


def weighted_demand_score(zone):
    """
    Idea 3 + 4 + 6: Combine all passenger demand signals into one score.

    Sources:
      - Active StopCheckIns (weighted by proximity)
      - Recent PassengerDemandReport of type high_demand / long_wait / stop_abandoned
        submitted in the last 30 minutes (weighted by proximity)

    Returns a float. Score >= 1.0 means real demand exists.
    """
    from core.models import StopCheckIn, PassengerDemandReport

    # Expire stale check-ins first
    StopCheckIn.expire_old_checkins()

    # Sum weighted check-ins
    checkin_score = sum(
        c.weight for c in StopCheckIn.objects.filter(zone=zone, is_active=True)
    )

    # Sum weighted demand reports from last 30 minutes
    cutoff = timezone.now() - timezone.timedelta(minutes=30)
    demand_types = [
        PassengerDemandReport.TYPE_HIGH_DEMAND,
        PassengerDemandReport.TYPE_LONG_WAIT,
        PassengerDemandReport.TYPE_STOP_ABANDONED,
    ]
    report_score = sum(
        r.weight for r in PassengerDemandReport.objects.filter(
            zone=zone,
            report_type__in=demand_types,
            created_at__gte=cutoff,
            is_processed=False,
        )
    )

    return checkin_score + report_score


def evaluate_zone(zone):
    """
    Evaluate zone status combining GPS supply AND passenger demand signals.

    GPS alone can miss situations where buses are present but not serving
    passengers (e.g. bus on route but not stopping, or bus full and passing).
    Passenger signals fill this gap.

    Returns:
        CRITICAL_LOW  - GPS supply=0 OR (supply < min AND strong passenger demand)
        LOW           - supply < min threshold
        HIGH          - supply > max AND no passenger demand signal
        OK            - balanced
    """
    threshold = get_active_threshold(zone)
    if not threshold:
        return 'OK'

    supply = len(buses_in_zone(zone))
    demand = weighted_demand_score(zone)

    if supply == 0 and demand >= 1.0:
        return 'CRITICAL_LOW'   # No buses at all + confirmed passenger demand
    elif supply < threshold.min_buses and demand >= 1.0:
        return 'CRITICAL_LOW'   # Not enough buses + passengers are waiting
    elif supply < threshold.min_buses:
        return 'LOW'            # Not enough buses (no passenger signal yet)
    elif supply > threshold.max_buses and demand < 0.5:
        return 'HIGH'           # Too many buses, nobody waiting
    return 'OK'


def find_best_bus_for_zone(target_zone, exclude_driver_ids=None):
    """
    Find the nearest on-route bus in a HIGH zone that could relocate
    to the target zone.

    Rules:
    - Driver must be on_route (not already relocating or offline)
    - Driver must NOT already be inside the target zone
    - Driver must NOT already have a pending relocation request to this zone
    - Driver must be in a HIGH or OK zone (not taking from another LOW zone)

    Returns (driver, distance_km) or (None, None).
    """
    from core.models import Driver, RelocationRequest

    exclude_driver_ids = exclude_driver_ids or []

    candidates = Driver.objects.filter(
        status=Driver.STATUS_ON_ROUTE,
        current_latitude__isnull=False,
        current_longitude__isnull=False,
    ).exclude(id__in=exclude_driver_ids).select_related('assigned_route', 'assigned_route__zone')

    best_driver   = None
    best_distance = float('inf')

    for driver in candidates:
        dist = haversine_km(
            driver.current_latitude, driver.current_longitude,
            target_zone.center_latitude, target_zone.center_longitude,
        )

        # Skip drivers already inside the target zone
        if dist <= target_zone.radius_km:
            continue

        # Skip drivers whose current zone is also LOW or CRITICAL_LOW
        if driver.assigned_route and driver.assigned_route.zone:
            driver_zone_status = evaluate_zone(driver.assigned_route.zone)
            if driver_zone_status in ('LOW', 'CRITICAL_LOW'):
                continue

        if dist < best_distance:
            best_distance = dist
            best_driver   = driver

    if best_driver is None:
        return None, None
    return best_driver, best_distance


def run_distribution():
    """
    Main distribution loop.
    Evaluates all zones and generates Ministry-pending relocation requests
    for zones that are CRITICAL_LOW or LOW.

    This does NOT automatically move buses — it creates a RelocationRequest
    that the Ministry must approve. This preserves regulatory compliance.

    Called by:
        - Celery beat every 5 minutes
        - Triggered when a driver goes on_route
    """
    from core.models import Zone, RelocationRequest

    for zone in Zone.objects.prefetch_related('thresholds').all():
        zone_status = evaluate_zone(zone)

        if zone_status not in ('CRITICAL_LOW', 'LOW'):
            continue

        # Drivers already assigned a pending relocation to this zone
        already_pending = list(
            RelocationRequest.objects.filter(
                to_zone=zone,
                status=RelocationRequest.STATUS_PENDING,
            ).values_list('driver_id', flat=True)
        )

        driver, distance = find_best_bus_for_zone(
            zone, exclude_driver_ids=already_pending
        )

        if driver is None:
            continue

        from_zone = driver.assigned_route.zone if driver.assigned_route else None

        RelocationRequest.objects.create(
            driver=driver,
            from_zone=from_zone,
            to_zone=zone,
            reason=f'System detected {zone_status} in {zone.name}. '
                   f'Nearest available bus is {distance:.1f} km away.',
            initiated_by=RelocationRequest.INITIATED_SYSTEM,
        )

        # Notify Ministry dashboard via WebSocket
        from realtime.push import push_relocation_recommendation
        push_relocation_recommendation(zone, zone_status, driver)


def expire_old_relocations():
    """
    Mark approved relocations as expired when their valid_until time has passed.
    Return expired drivers to on_route status.
    Called by Celery beat every 10 minutes.
    """
    from core.models import RelocationRequest, Driver

    now     = timezone.now()
    expired = RelocationRequest.objects.filter(
        status=RelocationRequest.STATUS_APPROVED,
        valid_until__lt=now,
    )

    for relocation in expired:
        relocation.status = RelocationRequest.STATUS_EXPIRED
        relocation.save(update_fields=['status'])

        # Return driver to on_route
        driver = relocation.driver
        if driver.status == Driver.STATUS_RELOCATING:
            driver.status = Driver.STATUS_ON_ROUTE
            driver.save(update_fields=['status'])


def restore_weekly_compliance():
    """
    Add 2 compliance points to every driver who had no confirmed violations
    this week. Rewards consistent compliance.
    Called by Celery beat weekly.
    """
    from core.models import Driver, RouteViolation

    one_week_ago = timezone.now() - timezone.timedelta(days=7)
    for driver in Driver.objects.all():
        had_violation_this_week = RouteViolation.objects.filter(
            driver=driver,
            status=RouteViolation.STATUS_CONFIRMED,
            detected_at__gte=one_week_ago,
        ).exists()

        if not had_violation_this_week:
            driver.restore_compliance(points=2)


def detect_offline_drivers():
    """
    Flag drivers who have not sent a GPS ping in 30+ minutes as offline.
    This catches drivers who turned off their app without logging out.
    Called by Celery beat every 15 minutes.
    """
    from core.models import Driver

    cutoff = timezone.now() - timezone.timedelta(minutes=30)
    stale_drivers = Driver.objects.filter(
        status__in=[Driver.STATUS_ON_ROUTE, Driver.STATUS_OFF_ROUTE, Driver.STATUS_RELOCATING],
        last_seen__lt=cutoff,
    )

    for driver in stale_drivers:
        driver.status = Driver.STATUS_OFFLINE
        driver.save(update_fields=['status'])

        # Notify dashboard
        from realtime.push import push_zone_update_to_dashboard
        if driver.assigned_route and driver.assigned_route.zone:
            zone        = driver.assigned_route.zone
            zone_status = evaluate_zone(zone)
            push_zone_update_to_dashboard(zone, zone_status)


def broadcast_all_zone_statuses():
    """
    Push current status of all zones to the Ministry dashboard.
    Called every 2 minutes to keep the live map updated.
    """
    from core.models import Zone
    from realtime.push import push_zone_update_to_dashboard

    for zone in Zone.objects.prefetch_related('thresholds').all():
        zone_status = evaluate_zone(zone)
        push_zone_update_to_dashboard(zone, zone_status)
