"""
Phase 2 Test Script — Ethiopian Public Minibus Monitoring System
================================================================
Tests:
  1.  REST GPS update (on-route)
  2.  REST GPS update (off-route) → violation + auto-dispatch
  3.  Zone demand summary (passenger map)
  4.  Celery task: run_distribution (zone evaluation)
  5.  Celery task: expire_checkins
  6.  Celery task: detect_offline_drivers
  7.  Celery task: expire_relocations
  8.  Celery task: weekly_compliance_restore
  9.  Celery task: broadcast_zone_status
  10. Full flow: GPS off-route → violation → auto-dispatch → inspector acknowledges → confirms → score drops
  11. Full flow: demand spike → distribution → relocation request created
  12. Periodic task schedule verification (tasks registered in DB)

Run with: python test_phase2.py
"""

import os, sys, django, json, requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'taxi_system.settings')
django.setup()

BASE = 'http://127.0.0.1:8000/api'

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN  = '\033[92m'
RED    = '\033[91m'
YELLOW = '\033[93m'
BLUE   = '\033[94m'
RESET  = '\033[0m'
BOLD   = '\033[1m'

def passed(label):  print(f'{GREEN}  ✅ PASS{RESET} — {label}')
def failed(label):  print(f'{RED}  ❌ FAIL{RESET} — {label}')
def info(msg):      print(f'{BLUE}  ℹ  {msg}{RESET}')
def section(title): print(f'\n{BOLD}{YELLOW}{"="*60}\n  {title}\n{"="*60}{RESET}')

def check(condition, label):
    if condition:
        passed(label)
    else:
        failed(label)
    return condition

def api(method, path, token=None, data=None, params=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    url = f'{BASE}{path}'
    r = getattr(requests, method)(url, json=data, headers=headers, params=params)
    return r

# ── Setup: ensure test data exists ───────────────────────────────────────────
section('SETUP — Preparing test data')

from core.models import (
    User, Driver, Inspector, Passenger, Zone, ZoneThreshold,
    Route, RouteWaypoint, RouteViolation, InspectorDispatch,
    RelocationRequest, StopCheckIn, PassengerDemandReport
)
from distribution.logic import evaluate_zone, weighted_demand_score
from django.utils import timezone
import datetime

# Zone
zone, _ = Zone.objects.get_or_create(
    name='Bole',
    defaults={'center_latitude': 9.0105, 'center_longitude': 38.7636, 'radius_km': 2.0}
)
zone2, _ = Zone.objects.get_or_create(
    name='Megenagna',
    defaults={'center_latitude': 9.0272, 'center_longitude': 38.7894, 'radius_km': 2.0}
)

# Threshold for today
now = timezone.localtime()
for z in [zone, zone2]:
    ZoneThreshold.objects.get_or_create(
        zone=z, day_of_week=now.weekday(), hour_start=0,
        defaults={'hour_end': 23, 'min_buses': 3, 'max_buses': 10}
    )

# Route
route, _ = Route.objects.get_or_create(
    name='Megenagna to Bole',
    defaults={'zone': zone, 'official_fare': 5.00, 'max_deviation_km': 0.3}
)
RouteWaypoint.objects.get_or_create(route=route, order=1, defaults={'latitude': 9.0272, 'longitude': 38.7894, 'label': 'Megenagna'})
RouteWaypoint.objects.get_or_create(route=route, order=2, defaults={'latitude': 9.0190, 'longitude': 38.7780, 'label': 'Midpoint'})
RouteWaypoint.objects.get_or_create(route=route, order=3, defaults={'latitude': 9.0105, 'longitude': 38.7636, 'label': 'Bole'})

# Users
def get_or_create_user(username, email, phone, role, password='Test1234!'):
    if not User.objects.filter(username=username).exists():
        payload = {
            'username': username, 'email': email, 'phone': phone,
            'role': role, 'password': password, 'password2': password,
        }
        if role == 'driver':
            payload['license_plate']  = 'AA-99999'
            payload['assigned_route'] = route.id
        if role == 'inspector':
            payload['badge_number']  = 'INS-TEST'
            payload['assigned_zone'] = zone.id
        r = api('post', '/auth/register/', data=payload)
        if r.status_code != 201:
            info(f'Register {username}: {r.json()}')
    r = api('post', '/auth/login/', data={'username': username, 'password': password})
    return r.json().get('access')

driver_token    = get_or_create_user('test_driver2',    'td2@test.com',  '+251944444441', 'driver')
inspector_token = get_or_create_user('test_inspector2', 'ti2@test.com',  '+251944444442', 'inspector')
passenger_token = get_or_create_user('test_passenger2', 'tp2@test.com',  '+251944444443', 'passenger')
admin_token     = api('post', '/auth/login/', data={'username': 'admin', 'password': 'admin123'}).json().get('access')

driver    = Driver.objects.get(user__username='test_driver2')
inspector = Inspector.objects.get(user__username='test_inspector2')
passenger = Passenger.objects.get(user__username='test_passenger2')

# Place inspector near Bole with GPS so auto-dispatch can find him
inspector.current_latitude  = 9.0200
inspector.current_longitude = 38.7700
inspector.is_available      = True
inspector.save()

# Reset driver to clean state
driver.status            = Driver.STATUS_ON_ROUTE
driver.current_latitude  = 9.0190
driver.current_longitude = 38.7780
driver.compliance_score  = 100
driver.assigned_route    = route
driver.save()

info(f'Driver:    {driver.license_plate} (score={driver.compliance_score})')
info(f'Inspector: {inspector.badge_number} at ({inspector.current_latitude}, {inspector.current_longitude})')
info(f'Zone:      {zone.name} — threshold min={3} max={10}')
info(f'Tokens:    driver={driver_token[:20]}...')


# ═══════════════════════════════════════════════════════════════════════════════
section('TEST 1 — REST GPS update: driver ON route')
# ═══════════════════════════════════════════════════════════════════════════════
# Midpoint of the route — should be on route
r = api('post', '/driver/location/', token=driver_token, data={'lat': 9.0190, 'lng': 38.7780})
check(r.status_code == 200, 'GPS update returns 200')
check(r.json().get('is_on_route') == True, 'is_on_route = True (driver is on his route)')
check(r.json().get('status') == 'on_route', 'driver status = on_route')
check('alert' not in r.json(), 'No violation alert (driver is compliant)')
info(f'Response: {r.json()}')


# ═══════════════════════════════════════════════════════════════════════════════
section('TEST 2 — REST GPS update: driver OFF route → violation + auto-dispatch')
# ═══════════════════════════════════════════════════════════════════════════════
# Clear existing open violations first
RouteViolation.objects.filter(driver=driver, status=RouteViolation.STATUS_OPEN).delete()

# Far from any waypoint — 5.5km off route
r = api('post', '/driver/location/', token=driver_token, data={'lat': 9.0600, 'lng': 38.8200})
check(r.status_code == 200, 'GPS update returns 200')
check(r.json().get('is_on_route') == False, 'is_on_route = False (driver left route)')
check(r.json().get('status') == 'off_route', 'driver status = off_route')
check('alert' in r.json(), 'Violation alert returned in response')
info(f'Alert message: {r.json().get("alert")}')

# Check violation was created
driver.refresh_from_db()
violation = RouteViolation.objects.filter(driver=driver).order_by('-detected_at').first()
check(violation is not None, 'RouteViolation created automatically')
check(violation.status in [RouteViolation.STATUS_OPEN, RouteViolation.STATUS_DISPATCHED],
      f'Violation status = {violation.status}')

# Check auto-dispatch
dispatch = InspectorDispatch.objects.filter(violation=violation).first()
check(dispatch is not None, 'InspectorDispatch created automatically (no Ministry action needed)')
if dispatch:
    check(dispatch.auto_dispatched == True, 'auto_dispatched = True (system dispatched, not Ministry)')
    # The system picks the NEAREST available inspector — could be any inspector with GPS set
    check(dispatch.inspector is not None, f'An inspector was dispatched: {dispatch.inspector.badge_number}')
    info(f'Dispatch: Inspector {dispatch.inspector.badge_number} → violation at ({violation.latitude}, {violation.longitude})')


# ═══════════════════════════════════════════════════════════════════════════════
section('TEST 3 — Zone demand summary (passenger app map)')
# ═══════════════════════════════════════════════════════════════════════════════
r = api('get', '/zones/demand/', token=passenger_token)
check(r.status_code == 200, 'Zone demand summary returns 200')
data = r.json()
check(isinstance(data, list), 'Returns a list of zones')
check(len(data) >= 1, f'At least 1 zone returned ({len(data)} zones)')

bole_data = next((z for z in data if z['zone_name'] == 'Bole'), None)
check(bole_data is not None, 'Bole zone in response')
if bole_data:
    check('status' in bole_data, 'Zone has status field')
    check('bus_count' in bole_data, 'Zone has bus_count field')
    check('demand_score' in bole_data, 'Zone has demand_score field')
    check('active_checkins' in bole_data, 'Zone has active_checkins field')
    info(f'Bole: status={bole_data["status"]}, buses={bole_data["bus_count"]}, demand={bole_data["demand_score"]}')


# ═══════════════════════════════════════════════════════════════════════════════
section('TEST 4 — Celery task: run_distribution')
# ═══════════════════════════════════════════════════════════════════════════════
# Bole has 0 on-route buses (driver is off-route) → should be CRITICAL_LOW
# run_distribution should create a RelocationRequest

# Clear existing pending relocations
RelocationRequest.objects.filter(to_zone=zone, status=RelocationRequest.STATUS_PENDING).delete()

# Put a second driver on-route in Megenagna (so there's someone to relocate)
# Make sure Megenagna zone has enough buses so it's not LOW itself
driver2_user, created = User.objects.get_or_create(
    username='test_driver3',
    defaults={'email': 'td3@test.com', 'phone': '+251944444450', 'role': 'driver'}
)
if created:
    driver2_user.set_password('Test1234!')
    driver2_user.save()

route2, _ = Route.objects.get_or_create(
    name='Megenagna Local',
    defaults={'zone': zone2, 'official_fare': 4.00, 'max_deviation_km': 0.5}
)
driver2, _ = Driver.objects.get_or_create(
    user=driver2_user,
    defaults={'license_plate': 'BB-11111', 'assigned_route': route2}
)
driver2.status            = Driver.STATUS_ON_ROUTE
driver2.current_latitude  = 9.0272   # Inside Megenagna zone
driver2.current_longitude = 38.7894
driver2.assigned_route    = route2
driver2.save()

# Add extra drivers to Megenagna so it's HIGH (oversupply) — then distribution
# will pick from there to send to Bole
for i, (lat, lng, plate) in enumerate([
    (9.0260, 38.7880, 'CC-22222'),
    (9.0280, 38.7900, 'CC-33333'),
    (9.0270, 38.7870, 'CC-44444'),
]):
    u, created = User.objects.get_or_create(
        username=f'extra_driver_{i}',
        defaults={'email': f'extra{i}@test.com', 'phone': f'+25194444{500+i}', 'role': 'driver'}
    )
    if created:
        u.set_password('Test1234!')
        u.save()
    d, _ = Driver.objects.get_or_create(user=u, defaults={'license_plate': plate, 'assigned_route': route2})
    d.status = Driver.STATUS_ON_ROUTE
    d.current_latitude  = lat
    d.current_longitude = lng
    d.assigned_route    = route2
    d.save()

from distribution.tasks import run_distribution_task
run_distribution_task()   # CELERY_TASK_ALWAYS_EAGER=True runs synchronously

relocation = RelocationRequest.objects.filter(
    to_zone=zone,
    status=RelocationRequest.STATUS_PENDING
).first()

check(relocation is not None, 'RelocationRequest created for CRITICAL_LOW zone')
if relocation:
    check(relocation.initiated_by == RelocationRequest.INITIATED_SYSTEM,
          'initiated_by = system (not driver)')
    check('CRITICAL_LOW' in relocation.reason or 'LOW' in relocation.reason,
          f'Reason mentions zone status: "{relocation.reason[:60]}..."')
    info(f'Relocation: {relocation.driver.license_plate} → {relocation.to_zone.name}')
    info(f'Reason: {relocation.reason}')


# ═══════════════════════════════════════════════════════════════════════════════
section('TEST 5 — Celery task: expire_checkins')
# ═══════════════════════════════════════════════════════════════════════════════
# Create a stale check-in (31 minutes ago)
old_checkin = StopCheckIn.objects.create(
    passenger=passenger,
    zone=zone,
    latitude=9.0105,
    longitude=38.7636,
    is_active=True,
)
# Manually backdate it
StopCheckIn.objects.filter(pk=old_checkin.pk).update(
    checked_in_at=timezone.now() - timezone.timedelta(minutes=31)
)

# Create a fresh check-in (just now — should NOT expire)
fresh_checkin = StopCheckIn.objects.create(
    passenger=passenger,
    zone=zone2,
    latitude=9.0272,
    longitude=38.7894,
    is_active=True,
)

from distribution.tasks import expire_checkins_task
expire_checkins_task()

old_checkin.refresh_from_db()
fresh_checkin.refresh_from_db()

check(old_checkin.is_active == False, 'Stale check-in (31 min old) expired correctly')
check(fresh_checkin.is_active == True, 'Fresh check-in (just now) NOT expired')
info(f'Old check-in is_active={old_checkin.is_active}, fresh is_active={fresh_checkin.is_active}')

# Cleanup
fresh_checkin.delete()


# ═══════════════════════════════════════════════════════════════════════════════
section('TEST 6 — Celery task: detect_offline_drivers')
# ═══════════════════════════════════════════════════════════════════════════════
# Create a driver who hasn't pinged in 31 minutes
ghost_user, created = User.objects.get_or_create(
    username='ghost_driver',
    defaults={'email': 'ghost@test.com', 'phone': '+251944444460', 'role': 'driver'}
)
if created:
    ghost_user.set_password('Test1234!')
    ghost_user.save()

ghost_driver, _ = Driver.objects.get_or_create(
    user=ghost_user,
    defaults={'license_plate': 'GH-00001', 'assigned_route': route}
)
ghost_driver.status           = Driver.STATUS_ON_ROUTE
ghost_driver.current_latitude = 9.0190
ghost_driver.current_longitude = 38.7780
ghost_driver.last_seen        = timezone.now() - timezone.timedelta(minutes=31)
ghost_driver.save()

from distribution.tasks import detect_offline_drivers_task
detect_offline_drivers_task()

ghost_driver.refresh_from_db()
check(ghost_driver.status == Driver.STATUS_OFFLINE,
      f'Ghost driver (no ping 31 min) marked offline (was on_route)')
info(f'Ghost driver status: {ghost_driver.status}')


# ═══════════════════════════════════════════════════════════════════════════════
section('TEST 7 — Celery task: expire_relocations')
# ═══════════════════════════════════════════════════════════════════════════════
# Create an approved relocation that expired 1 minute ago
expired_relocation = RelocationRequest.objects.create(
    driver=driver2,
    from_zone=zone2,
    to_zone=zone,
    reason='Test expired relocation',
    initiated_by=RelocationRequest.INITIATED_SYSTEM,
    status=RelocationRequest.STATUS_APPROVED,
    valid_until=timezone.now() - timezone.timedelta(minutes=1),
)
driver2.status = Driver.STATUS_RELOCATING
driver2.save()

from distribution.tasks import expire_relocations_task
expire_relocations_task()

expired_relocation.refresh_from_db()
driver2.refresh_from_db()

check(expired_relocation.status == RelocationRequest.STATUS_EXPIRED,
      'Expired relocation marked as EXPIRED')
check(driver2.status == Driver.STATUS_ON_ROUTE,
      'Driver returned to on_route after relocation expired')
info(f'Relocation status: {expired_relocation.status}, driver status: {driver2.status}')


# ═══════════════════════════════════════════════════════════════════════════════
section('TEST 8 — Celery task: weekly_compliance_restore')
# ═══════════════════════════════════════════════════════════════════════════════
# driver2 has no confirmed violations this week — should get +2 points
driver2.compliance_score = 80
driver2.save()

from distribution.tasks import weekly_compliance_restore_task
weekly_compliance_restore_task()

driver2.refresh_from_db()
check(driver2.compliance_score == 82,
      f'Clean driver score restored: 80 → {driver2.compliance_score} (expected 82)')

# driver (test_driver2) has a confirmed violation — should NOT get points
# First confirm the violation
violation.refresh_from_db()
if violation.status not in [RouteViolation.STATUS_CONFIRMED, RouteViolation.STATUS_DISMISSED]:
    violation.confirm(inspector=inspector, notes='Test confirmation')

driver.refresh_from_db()
score_before = driver.compliance_score
weekly_compliance_restore_task()
driver.refresh_from_db()
check(driver.compliance_score == score_before,
      f'Driver with confirmed violation did NOT get points (score stayed at {score_before})')


# ═══════════════════════════════════════════════════════════════════════════════
section('TEST 9 — Celery task: broadcast_zone_status')
# ═══════════════════════════════════════════════════════════════════════════════
# This task pushes to WebSocket (Redis). Without Redis it should fail silently.
from distribution.tasks import broadcast_zone_status_task
try:
    broadcast_zone_status_task()
    passed('broadcast_zone_status runs without crashing (Redis push skipped silently)')
except Exception as e:
    failed(f'broadcast_zone_status crashed: {e}')


# ═══════════════════════════════════════════════════════════════════════════════
section('TEST 10 — Full flow: GPS off-route → auto-dispatch → inspector confirms')
# ═══════════════════════════════════════════════════════════════════════════════
# Reset driver
driver.status            = Driver.STATUS_ON_ROUTE
driver.compliance_score  = 100
driver.current_latitude  = 9.0190
driver.current_longitude = 38.7780
driver.save()
RouteViolation.objects.filter(driver=driver, status=RouteViolation.STATUS_OPEN).delete()
inspector.is_available = True
inspector.save()

# Step 1: Driver goes off route via REST
r = api('post', '/driver/location/', token=driver_token, data={'lat': 9.0700, 'lng': 38.8300})
check(r.json().get('is_on_route') == False, 'Step 1: Driver went off route')

# Step 2: Violation created
violation2 = RouteViolation.objects.filter(driver=driver, status__in=[
    RouteViolation.STATUS_OPEN, RouteViolation.STATUS_DISPATCHED
]).order_by('-detected_at').first()
check(violation2 is not None, 'Step 2: Violation created automatically')

# Step 3: Auto-dispatch created
dispatch2 = InspectorDispatch.objects.filter(violation=violation2).first()
check(dispatch2 is not None, 'Step 3: Inspector auto-dispatched')
check(dispatch2 is not None and dispatch2.auto_dispatched, 'Step 3: auto_dispatched=True')

# Step 4: Inspector acknowledges via API
if dispatch2:
    # Use whichever inspector was auto-dispatched
    dispatched_inspector = dispatch2.inspector
    dispatched_inspector_token = api('post', '/auth/login/', data={
        'username': dispatched_inspector.user.username, 'password': 'Test1234!'
    }).json().get('access') or inspector_token

    r = api('patch', f'/inspector/dispatches/{dispatch2.id}/respond/',
            token=dispatched_inspector_token, data={'action': 'acknowledge'})
    check(r.status_code == 200, 'Step 4: Inspector acknowledged dispatch')
    dispatched_inspector.refresh_from_db()
    check(dispatched_inspector.is_available == False, 'Step 4: Inspector marked as busy')

# Step 5: Inspector confirms violation via API
r = api('post', '/inspector/violations/record/', token=dispatched_inspector_token, data={
    'plate_number': driver.license_plate,
    'action': 'confirm',
    'notes': 'Full flow test — bus confirmed off route in Gerji area',
})
check(r.status_code == 200, 'Step 5: Inspector confirmed violation')

# Step 6: Compliance score dropped
driver.refresh_from_db()
check(driver.compliance_score < 100,
      f'Step 6: Compliance score dropped to {driver.compliance_score} (was 100)')

# Step 7: Inspector freed up
dispatched_inspector.refresh_from_db()
check(dispatched_inspector.is_available == True, 'Step 7: Inspector available again after confirmation')

info(f'Final driver score: {driver.compliance_score}')
info(f'Final inspector available: {dispatched_inspector.is_available}')


# ═══════════════════════════════════════════════════════════════════════════════
section('TEST 11 — Full flow: demand spike → distribution → relocation request')
# ═══════════════════════════════════════════════════════════════════════════════
# Clear pending relocations
RelocationRequest.objects.filter(to_zone=zone, status=RelocationRequest.STATUS_PENDING).delete()

# Step 1: Passenger checks in at Bole (demand signal)
r = api('post', '/stop/checkin/', token=passenger_token, data={
    'zone': zone.id,
    'latitude': 9.0105,
    'longitude': 38.7636,
})
check(r.status_code == 201, 'Step 1: Passenger checked in at Bole stop')
check(r.json().get('weight') == 1.0, f'Step 1: Weight = {r.json().get("weight")} (reporter inside zone)')

# Step 2: Passenger submits demand report
r = api('post', '/demand/report/', token=passenger_token, data={
    'zone': zone.id,
    'report_type': 'long_wait',
    'description': 'Waiting 25 minutes at Bole. 30+ people here.',
    'reporter_latitude': 9.0105,
    'reporter_longitude': 38.7636,
})
check(r.status_code == 201, 'Step 2: Demand report submitted')
check(r.json().get('weight') == 1.0, f'Step 2: Weight = {r.json().get("weight")} (trusted report)')

# Step 3: Check weighted demand score
demand = weighted_demand_score(zone)
check(demand >= 1.0, f'Step 3: Weighted demand score = {demand:.2f} (≥ 1.0 means real demand)')

# Step 4: Evaluate zone — should be CRITICAL_LOW
zone_status = evaluate_zone(zone)
check(zone_status in ('CRITICAL_LOW', 'LOW'),
      f'Step 4: Zone status = {zone_status} (demand + no buses = underserved)')

# Step 5: Run distribution — should create relocation request
# Reset driver2 to on_route in Megenagna
driver2.status            = Driver.STATUS_ON_ROUTE
driver2.current_latitude  = 9.0272
driver2.current_longitude = 38.7894
driver2.save()

run_distribution_task()

relocation2 = RelocationRequest.objects.filter(
    to_zone=zone,
    status=RelocationRequest.STATUS_PENDING
).order_by('-requested_at').first()

check(relocation2 is not None, 'Step 5: RelocationRequest created for underserved zone')
if relocation2:
    info(f'Relocation: {relocation2.driver.license_plate} → {relocation2.to_zone.name}')
    info(f'Reason: {relocation2.reason}')

# Step 6: Ministry approves via API
if relocation2:
    r = api('post', f'/ministry/relocation/{relocation2.id}/decide/',
            token=admin_token, data={'action': 'approve', 'valid_hours': 2})
    check(r.status_code == 200, 'Step 6: Ministry approved relocation')
    check('valid_until' in r.json(), 'Step 6: valid_until returned in response')
    info(f'Approved until: {r.json().get("valid_until")}')

    relocation2.driver.refresh_from_db()
    check(relocation2.driver.status == Driver.STATUS_RELOCATING,
          f'Step 6: Driver status = {relocation2.driver.status} (relocating to Bole)')


# ═══════════════════════════════════════════════════════════════════════════════
section('TEST 12 — Periodic task schedule verification')
# ═══════════════════════════════════════════════════════════════════════════════
from django_celery_beat.models import PeriodicTask

expected_tasks = [
    'Run Distribution (every 5 min)',
    'Expire Relocations (every 10 min)',
    'Expire Stop Check-ins (every 5 min)',
    'Detect Offline Drivers (every 15 min)',
    'Broadcast Zone Status (every 2 min)',
    'Weekly Compliance Restore (Monday 00:00)',
]

for task_name in expected_tasks:
    exists = PeriodicTask.objects.filter(name=task_name, enabled=True).exists()
    check(exists, f'Periodic task registered: "{task_name}"')


# ═══════════════════════════════════════════════════════════════════════════════
section('SUMMARY')
# ═══════════════════════════════════════════════════════════════════════════════
print(f'\n{BOLD}Phase 2 tests complete.{RESET}')
print(f'\nTo run with Redis + real Celery workers:')
print(f'  Terminal 1: {BLUE}celery -A taxi_system worker -l info{RESET}')
print(f'  Terminal 2: {BLUE}celery -A taxi_system beat -l info{RESET}')
print(f'  Then set:   {BLUE}CELERY_TASK_ALWAYS_EAGER=False{RESET} in .env')
print(f'\nAll tasks currently run synchronously (CELERY_TASK_ALWAYS_EAGER=True)')
print(f'This is correct for development — no Redis needed.\n')
