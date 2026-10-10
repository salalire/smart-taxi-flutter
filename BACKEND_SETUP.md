# Backend Setup Guide

The Flutter app talks to a Django backend located at:

```
~/Salah/samuel/githubrepos/real2/Smart-Taxi-Distribution-System/backend/
```

---

## Prerequisites

| Tool | Notes |
|------|-------|
| Python 3.11+ | `python3 --version` |
| Redis | `sudo apt install redis-server` then `sudo systemctl start redis` |
| SQLite | Included with Python — no extra install needed for development |

> PostgreSQL is **not** required for local development.  
> The backend defaults to SQLite (`USE_SQLITE=True` in `settings.py`).

---

## First-time setup

```bash
cd ~/Salah/samuel/githubrepos/real2/Smart-Taxi-Distribution-System/backend

# 1. Create and activate virtual environment
python3 -m venv venv
source venv/bin/activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Copy environment file (edit values if needed)
cp .env.example .env

# 4. Run database migrations
python manage.py migrate

# 5. Create a superuser / Ministry Admin account
python manage.py createsuperuser
#    When prompted for role, use: ministry_admin
#    (or set it in the Django admin after creation)
```

---

## Running the backend

Open **three terminals**, all with `source venv/bin/activate` active:

**Terminal 1 — Django dev server**
```bash
cd ~/Salah/samuel/githubrepos/real2/Smart-Taxi-Distribution-System/backend
source venv/bin/activate
python manage.py runserver 0.0.0.0:8000
```

**Terminal 2 — Celery worker** (background tasks: zone evaluation, expiry)
```bash
cd ~/Salah/samuel/githubrepos/real2/Smart-Taxi-Distribution-System/backend
source venv/bin/activate
celery -A taxi_system worker -l info
```

**Terminal 3 — Celery beat** (periodic scheduler)
```bash
cd ~/Salah/samuel/githubrepos/real2/Smart-Taxi-Distribution-System/backend
source venv/bin/activate
celery -A taxi_system beat -l info
```

> Celery + Redis are only needed for zone redistribution and relocation expiry.  
> The core REST API and WebSockets work without them in development  
> (`CELERY_TASK_ALWAYS_EAGER=True` is already set in `settings.py`).

---

## Connecting the Flutter app

Edit `lib/core/auth/auth_provider.dart` and set the correct IP:

```dart
// Android emulator (default)
const kApiBaseUrl = 'http://10.0.2.2:8000';
const kWsBaseUrl  = 'ws://10.0.2.2:8000';

// Physical device on the same Wi-Fi network — replace with your machine's IP
// const kApiBaseUrl = 'http://192.168.x.x:8000';
// const kWsBaseUrl  = 'ws://192.168.x.x:8000';
```

Find your machine's IP with:
```bash
ip route get 1.1.1.1 | awk '{print $7; exit}'
```

---

## API quick-reference

| Base URL | Purpose |
|----------|---------|
| `http://<host>:8000/api/auth/login/` | JWT login — returns `access`, `refresh`, `role` |
| `http://<host>:8000/api/auth/register/` | Register driver / passenger / inspector |
| `http://<host>:8000/admin/` | Django admin panel |
| `ws://<host>:8000/ws/driver/?token=<jwt>` | Driver WebSocket |
| `ws://<host>:8000/ws/inspector/?token=<jwt>` | Inspector WebSocket |
| `ws://<host>:8000/ws/dashboard/?token=<jwt>` | Ministry dashboard WebSocket |

---

## Seeding test data

The Django admin at `http://localhost:8000/admin/` lets you create:
- **Zones** — add at least one zone with a center lat/lng and radius
- **Routes** — assign a zone and add waypoints
- **Drivers** — create a user with role `driver`, attach a route and plate
- **ZoneThresholds** — set min/max bus counts per day/hour so zone evaluation works

Alternatively use the simulate GPS script included in the backend:
```bash
python simulate_gps.py
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `ModuleNotFoundError: No module named 'whitenoise'` | `pip install -r requirements.txt` again — whitenoise was added |
| `django.core.exceptions.ImproperlyConfigured: ... channels_redis` | Start Redis: `sudo systemctl start redis` |
| Flutter gets `SocketException: Connection refused` | Check `kApiBaseUrl` in `auth_provider.dart` matches your server IP |
| WebSocket never connects | Confirm you are running `python manage.py runserver` with `daphne` or via ASGI — plain WSGI does not support WebSockets |
| `401 Unauthorized` on every request | Token expired or wrong — log out and back in |
