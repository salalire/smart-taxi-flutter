"""
GPS simulation script.
Simulates a driver sending a location update through the full system logic.
This triggers on-route detection and violation creation automatically.

Usage:
    python simulate_gps.py on_route     <- driver is on his route (no violation)
    python simulate_gps.py off_route    <- driver is off his route (violation created)
"""

import os, sys, django
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'taxi_system.settings')
django.setup()

from core.models import Driver, RouteViolation

# ── Get samuel's driver profile ───────────────────────────────────────────────
try:
    driver = Driver.objects.get(license_plate='AA-12345')
except Driver.DoesNotExist:
    print("ERROR: Driver with plate AA-12345 not found.")
    print("Make sure you completed Step 5 (register driver) first.")
    sys.exit(1)

mode = sys.argv[1] if len(sys.argv) > 1 else 'off_route'

if mode == 'on_route':
    # ── Midpoint of Megenagna→Bole route — exactly on route ──────────────────
    lat, lng = 9.0190, 38.7780
    print(f"\nSimulating ON-ROUTE GPS update for {driver.license_plate}")
    print(f"Position: ({lat}, {lng}) — midpoint of assigned route")
else:
    # ── Far from any waypoint — clearly off route ─────────────────────────────
    lat, lng = 9.0600, 38.8200
    print(f"\nSimulating OFF-ROUTE GPS update for {driver.license_plate}")
    print(f"Position: ({lat}, {lng}) — 5.5km from nearest waypoint")

# ── Run through the full update_location() logic ─────────────────────────────
driver.status = 'on_route'   # make sure driver is active before the update
driver.save(update_fields=['status'])

location_update = driver.update_location(lat, lng)

# ── Show results ──────────────────────────────────────────────────────────────
driver.refresh_from_db()

print(f"\n{'='*50}")
print(f"Result:")
print(f"  is_on_route  : {location_update.is_on_route}")
print(f"  driver status: {driver.status}")
print(f"  compliance   : {driver.compliance_score}")

violations = RouteViolation.objects.filter(driver=driver).order_by('-detected_at')
print(f"  total violations: {violations.count()}")

if violations.exists():
    v = violations.first()
    print(f"\n  Latest violation:")
    print(f"    ID       : {v.id}")
    print(f"    Status   : {v.status}")
    print(f"    Location : ({v.latitude}, {v.longitude})")
    print(f"    Detected : {v.detected_at}")
    print(f"\n  ✅ Violation created! Now go to:")
    print(f"     Admin → Route Violations  (you will see it there)")
    print(f"     GET /api/ministry/violations/  (you will see it in the API)")
else:
    print(f"\n  ✅ No violation — driver is on route.")

print(f"{'='*50}\n")
