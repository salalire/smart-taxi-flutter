"""
Push helpers — send messages to WebSocket clients via the channel layer.
All functions fail silently if Redis is not available.
"""

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer


def _redis_available():
    try:
        import redis as redis_lib
        from django.conf import settings
        hosts = settings.CHANNEL_LAYERS.get('default', {}).get('CONFIG', {}).get('hosts', [])
        if not hosts:
            return False
        url = hosts[0] if isinstance(hosts[0], str) else 'redis://localhost:6379/0'
        redis_lib.from_url(url).ping()
        return True
    except Exception:
        return False


def _send(group, payload):
    """Send a message to a channel layer group. Fails silently."""
    if not _redis_available():
        return
    channel_layer = get_channel_layer()
    if not channel_layer:
        return
    try:
        async_to_sync(channel_layer.group_send)(group, payload)
    except Exception:
        pass


def push_violation_alert_to_driver(driver):
    """Alert driver that they have left their assigned route."""
    _send(
        f'driver_{driver.user.id}',
        {
            'type':    'violation_alert',
            'message': 'You have left your assigned route. Please return immediately.',
        }
    )


def push_relocation_decision(relocation):
    """Push Ministry's approval or rejection to the driver."""
    if relocation.status == 'approved':
        _send(
            f'driver_{relocation.driver.user.id}',
            {
                'type':        'relocation_approved',
                'to_zone':     relocation.to_zone.name,
                'valid_until': str(relocation.valid_until),
            }
        )
    elif relocation.status == 'rejected':
        _send(
            f'driver_{relocation.driver.user.id}',
            {
                'type':   'relocation_rejected',
                'reason': relocation.rejection_reason or 'Request rejected by Ministry.',
            }
        )


def push_dispatch_to_inspector(inspector, dispatch):
    """Send a dispatch alert to a specific inspector."""
    violation = dispatch.violation
    _send(
        f'inspector_{inspector.user.id}',
        {
            'type':         'dispatch_alert',
            'dispatch_id':  dispatch.id,
            'violation_id': violation.id,
            'plate':        violation.driver.license_plate,
            'lat':          violation.latitude,
            'lng':          violation.longitude,
        }
    )


def push_relocation_recommendation(zone, zone_status, driver):
    """Notify Ministry dashboard that a relocation recommendation was generated."""
    _send(
        'dashboard',
        {
            'type':         'relocation_recommendation',
            'zone':         zone.name,
            'zone_status':  zone_status,
            'driver_plate': driver.license_plate,
        }
    )


def push_violation_to_dashboard(violation):
    """Broadcast a new violation detection to the Ministry dashboard."""
    _send(
        'dashboard',
        {
            'type':         'violation_detected',
            'violation_id': violation.id,
            'plate':        violation.driver.license_plate,
            'lat':          violation.latitude,
            'lng':          violation.longitude,
        }
    )


def push_zone_update_to_dashboard(zone, zone_status):
    """Broadcast a zone status update to the Ministry dashboard."""
    from distribution.logic import buses_in_zone
    _send(
        'dashboard',
        {
            'type':      'zone_update',
            'zone_id':   zone.id,
            'zone_name': zone.name,
            'status':    zone_status,
            'bus_count': len(buses_in_zone(zone)),
        }
    )
