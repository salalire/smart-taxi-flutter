"""
Management command to set up all Celery beat periodic tasks in the database.
Run once after deployment: python manage.py setup_periodic_tasks

This replaces manual configuration in Django admin.
"""

from django.core.management.base import BaseCommand
from django_celery_beat.models import PeriodicTask, IntervalSchedule, CrontabSchedule
import json


class Command(BaseCommand):
    help = 'Set up all Celery beat periodic tasks for the transport system'

    def handle(self, *args, **kwargs):
        self.stdout.write('Setting up periodic tasks...')

        # --- Every 5 minutes ---
        every_5, _ = IntervalSchedule.objects.get_or_create(
            every=5, period=IntervalSchedule.MINUTES
        )
        # --- Every 10 minutes ---
        every_10, _ = IntervalSchedule.objects.get_or_create(
            every=10, period=IntervalSchedule.MINUTES
        )
        # --- Every 15 minutes ---
        every_15, _ = IntervalSchedule.objects.get_or_create(
            every=15, period=IntervalSchedule.MINUTES
        )
        # --- Every 2 minutes ---
        every_2, _ = IntervalSchedule.objects.get_or_create(
            every=2, period=IntervalSchedule.MINUTES
        )
        # --- Weekly: Monday at 00:00 ---
        weekly_monday, _ = CrontabSchedule.objects.get_or_create(
            minute='0', hour='0',
            day_of_week='1',       # Monday
            day_of_month='*',
            month_of_year='*',
        )

        tasks = [
            {
                'name':      'Run Distribution (every 5 min)',
                'task':      'distribution.run_distribution',
                'schedule':  every_5,
                'schedule_type': 'interval',
            },
            {
                'name':      'Expire Relocations (every 10 min)',
                'task':      'distribution.expire_relocations',
                'schedule':  every_10,
                'schedule_type': 'interval',
            },
            {
                'name':      'Expire Stop Check-ins (every 5 min)',
                'task':      'distribution.expire_checkins',
                'schedule':  every_5,
                'schedule_type': 'interval',
            },
            {
                'name':      'Detect Offline Drivers (every 15 min)',
                'task':      'distribution.detect_offline_drivers',
                'schedule':  every_15,
                'schedule_type': 'interval',
            },
            {
                'name':      'Broadcast Zone Status (every 2 min)',
                'task':      'distribution.broadcast_zone_status',
                'schedule':  every_2,
                'schedule_type': 'interval',
            },
            {
                'name':      'Weekly Compliance Restore (Monday 00:00)',
                'task':      'distribution.weekly_compliance_restore',
                'schedule':  weekly_monday,
                'schedule_type': 'crontab',
            },
        ]

        for task_def in tasks:
            schedule_type = task_def.pop('schedule_type')
            schedule      = task_def.pop('schedule')

            kwargs_create = {
                'task':    task_def['task'],
                'enabled': True,
                'args':    json.dumps([]),
            }
            if schedule_type == 'interval':
                kwargs_create['interval'] = schedule
            else:
                kwargs_create['crontab'] = schedule

            obj, created = PeriodicTask.objects.update_or_create(
                name=task_def['name'],
                defaults=kwargs_create,
            )
            status = 'Created' if created else 'Updated'
            self.stdout.write(f'  {status}: {task_def["name"]}')

        self.stdout.write(self.style.SUCCESS('\nAll periodic tasks configured successfully.'))
        self.stdout.write('Start Celery worker:  celery -A taxi_system worker -l info')
        self.stdout.write('Start Celery beat:    celery -A taxi_system beat -l info')
