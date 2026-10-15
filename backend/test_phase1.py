"""
Phase 1 manual test script.
Run with: python test_phase1.py

Tests every endpoint in order:
  1. Register a driver
  2. Register a passenger
  3. Login as driver  → get JWT
  4. Login as passenger → get JWT
  5. Driver updates status to idle
  6. Passenger requests a ride (needs a zone first — script creates one via Django ORM)
  7. Passenger checks ride status
  8. Driver gets suggestions
  9. Passenger cancels ride
  10. Get all zones
  11. Get dashboard stats
"""

import os
import sys
import django

# ── Bootstrap Django so we can use ORM directly ──────────────────────────────
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'taxi_system.settings')
django.setup()

import requests
import json

BASE = 'http://127.0.0.1:8000/api'

# ── Helpers ───────────────────────────────────────────────────────────────────

def ok(label, response, expected_status=None):
    status = response.status_code
    color  = '\033[92m' if (expected_status is None and status < 400) or status == expected_status else '\033[91m'
    reset  = '\033[0m'
    try:
        body = response.json()
    except Exception:
        body = response.text
    print(f'{color}[{status}] {label}{reset}')
    print(f'       {json.dumps(body, indent=2)[:300]}')
    print()
    return body

def auth_header(token):
    return {'Authorization': f'Bearer {token}'}

# ── Seed: create a Zone so ride requests have somewhere to go ─────────────────
from core.models import Zone, ZoneThreshold

print('=' * 60)
print('SEEDING: Creating test zone...')
zone, created = Zone.objects.get_or_create(
    name='Bole',
    defaults={
        'center_latitude':  9.0105,
        'center_longitude': 38.7636,
        'radius_km':        2.0,
    }
)
# Add a threshold for every hour of every day so evaluate_zone always has data
for day in range(7):
    ZoneThreshold.objects.get_or_create(
        zone=zone, day_of_week=day, hour_start=0,
        defaults={'hour_end': 23, 'min_taxis': 2, 'max_taxis': 8}
    )
print(f'  Zone "{zone.name}" ready (id={zone.id})\n')

# ── 1. Register driver ────────────────────────────────────────────────────────
print('=' * 60)
print('TEST 1 — Register driver')
r = requests.post(f'{BASE}/auth/register/', json={
    'username':  'driver_test',
    'email':     'driver@test.com',
    'phone':     '+251911000001',
    'role':      'driver',
    'password':  'StrongPass123!',
    'password2': 'StrongPass123!',
})
ok('Register driver', r, 201)

# ── 2. Register passenger ─────────────────────────────────────────────────────
print('TEST 2 — Register passenger')
r = requests.post(f'{BASE}/auth/register/', json={
    'username':  'passenger_test',
    'email':     'passenger@test.com',
    'phone':     '+251911000002',
    'role':      'passenger',
    'password':  'StrongPass123!',
    'password2': 'StrongPass123!',
})
ok('Register passenger', r, 201)

# ── 3. Login as driver ────────────────────────────────────────────────────────
print('TEST 3 — Login as driver')
r = requests.post(f'{BASE}/auth/login/', json={
    'username': 'driver_test',
    'password': 'StrongPass123!',
})
driver_data  = ok('Login driver', r, 200)
driver_token = driver_data.get('access', '')

# ── 4. Login as passenger ─────────────────────────────────────────────────────
print('TEST 4 — Login as passenger')
r = requests.post(f'{BASE}/auth/login/', json={
    'username': 'passenger_test',
    'password': 'StrongPass123!',
})
passenger_data  = ok('Login passenger', r, 200)
passenger_token = passenger_data.get('access', '')

# ── 5. Driver updates status to idle ─────────────────────────────────────────
print('TEST 5 — Driver sets status to idle')
r = requests.patch(
    f'{BASE}/driver/status/',
    json={'status': 'idle'},
    headers=auth_header(driver_token),
)
ok('Driver status → idle', r, 200)

# ── 6. Driver updates location (near Bole zone) ───────────────────────────────
print('TEST 6 — Driver updates location (via ORM, WebSocket tested separately)')
from core.models import Driver as DriverModel
driver_obj = DriverModel.objects.get(user__username='driver_test')
driver_obj.update_location(9.0200, 38.7700)   # ~1 km from Bole center
print(f'  Driver location set to (9.0200, 38.7700)\n')

# ── 7. Passenger requests a ride ──────────────────────────────────────────────
print('TEST 7 — Passenger requests a ride')
r = requests.post(
    f'{BASE}/rides/request/',
    json={
        'pickup_latitude':  9.0105,
        'pickup_longitude': 38.7636,
    },
    headers=auth_header(passenger_token),
)
ride_data = ok('Request ride', r, 201)
ride_id   = ride_data.get('id')

# ── 8. Passenger checks ride status ──────────────────────────────────────────
print('TEST 8 — Passenger checks ride status')
r = requests.get(
    f'{BASE}/rides/{ride_id}/',
    headers=auth_header(passenger_token),
)
ok('Ride detail', r, 200)

# ── 9. Driver checks suggestions ─────────────────────────────────────────────
print('TEST 9 — Driver checks suggestions')
r = requests.get(
    f'{BASE}/driver/suggestions/',
    headers=auth_header(driver_token),
)
suggestions = ok('Driver suggestions', r, 200)
suggestion_id = suggestions[0]['id'] if suggestions else None

# ── 10. Driver responds to suggestion (if any) ────────────────────────────────
if suggestion_id:
    print('TEST 10 — Driver accepts suggestion')
    r = requests.post(
        f'{BASE}/driver/suggestions/{suggestion_id}/respond/',
        json={'action': 'accepted'},
        headers=auth_header(driver_token),
    )
    ok('Accept suggestion', r, 200)
else:
    print('TEST 10 — No suggestions yet (Celery not running, trigger manually)\n')

# ── 11. Passenger cancels ride ────────────────────────────────────────────────
print('TEST 11 — Passenger cancels ride')
r = requests.delete(
    f'{BASE}/rides/{ride_id}/cancel/',
    headers=auth_header(passenger_token),
)
ok('Cancel ride', r, 200)

# ── 12. Get all zones ─────────────────────────────────────────────────────────
print('TEST 12 — Get all zones')
r = requests.get(
    f'{BASE}/zones/',
    headers=auth_header(driver_token),
)
ok('Zone list', r, 200)

# ── 13. Get dashboard ─────────────────────────────────────────────────────────
print('TEST 13 — Get dashboard stats')
r = requests.get(
    f'{BASE}/dashboard/',
    headers=auth_header(driver_token),
)
ok('Dashboard', r, 200)

# ── 14. Test duplicate registration (should fail) ────────────────────────────
print('TEST 14 — Duplicate registration (expect 400)')
r = requests.post(f'{BASE}/auth/register/', json={
    'username':  'driver_test',
    'email':     'driver@test.com',
    'phone':     '+251911000001',
    'role':      'driver',
    'password':  'StrongPass123!',
    'password2': 'StrongPass123!',
})
ok('Duplicate register (should be 400)', r, 400)

# ── 15. Test wrong password (should fail) ────────────────────────────────────
print('TEST 15 — Wrong password login (expect 401)')
r = requests.post(f'{BASE}/auth/login/', json={
    'username': 'driver_test',
    'password': 'wrongpassword',
})
ok('Wrong password (should be 401)', r, 401)

# ── 16. Test unauthenticated access (should fail) ────────────────────────────
print('TEST 16 — Unauthenticated access (expect 401)')
r = requests.get(f'{BASE}/zones/')
ok('No token (should be 401)', r, 401)

print('=' * 60)
print('All tests complete.')
print('=' * 60)
