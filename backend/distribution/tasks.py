"""
Celery background tasks for the distribution app.

Schedule (configured via Django admin → Periodic Tasks):
    run_distribution_task          every 5 minutes
    expire_relocations_task        every 10 minutes
    expire_checkins_task           every 5 minutes
    detect_offline_drivers_task    every 15 minutes
    weekly_compliance_restore_task every Monday at 00:00
    broadcast_zone_status_task     every 2 minutes (keeps dashboard live)
"""

from celery import shared_task


@shared_task(name='distribution.run_distribution')
def run_distribution_task():
    """
    Evaluate all zones and generate relocation recommendations for Ministry.
    Combines GPS supply + passenger demand signals.
    """
    from distribution.logic import run_distribution
    run_distribution()


@shared_task(name='distribution.expire_relocations')
def expire_relocations_task():
    """
    Expire relocation permits that have passed their valid_until time.
    Returns drivers to on_route status automatically.
    """
    from distribution.logic import expire_old_relocations
    expire_old_relocations()


@shared_task(name='distribution.expire_checkins')
def expire_checkins_task():
    """
    Mark stop check-ins older than 30 minutes as inactive.
    Keeps demand signal fresh and accurate.
    """
    from core.models import StopCheckIn
    StopCheckIn.expire_old_checkins()


@shared_task(name='distribution.detect_offline_drivers')
def detect_offline_drivers_task():
    """
    Flag drivers who have not sent a GPS ping in 30+ minutes as offline.
    This catches drivers who turned off their app without logging out.
    A driver going offline without logging out is itself a compliance signal.
    """
    from distribution.logic import detect_offline_drivers
    detect_offline_drivers()


@shared_task(name='distribution.weekly_compliance_restore')
def weekly_compliance_restore_task():
    """
    Restore 2 compliance points to drivers with no confirmed violations this week.
    Rewards consistent compliance over time.
    """
    from distribution.logic import restore_weekly_compliance
    restore_weekly_compliance()


@shared_task(name='distribution.broadcast_zone_status')
def broadcast_zone_status_task():
    """
    Broadcast current zone status to all Ministry dashboard clients.
    Keeps the live map updated even when no GPS events are happening.
    """
    from distribution.logic import broadcast_all_zone_statuses
    broadcast_all_zone_statuses()
