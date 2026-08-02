# 🚌 Smart Taxi — Unified Flutter App

A single **role-based Flutter app** replacing three separate Java Android apps for the **Ethiopian Public Minibus Monitoring & Distribution System**.

One APK. Four roles. All functionality.

---

## 🎯 What This Replaces

| Before | After |
|---|---|
| Driver App (Java) | ✅ Driver shell in Flutter |
| Passenger App (Java) | ✅ Passenger shell in Flutter |
| Inspector App (Java) | ✅ Inspector shell in Flutter |
| — | ✅ Ministry Admin shell (new) |

The backend (Django + Django Channels + PostgreSQL + Redis + Celery) and the web dashboard (Leaflet.js) are **unchanged**.

---

## 📱 How It Works

```
Login screen
     ↓
JWT response contains role claim
     ↓
     ├── driver        → Driver Shell
     ├── passenger     → Passenger Shell
     ├── inspector     → Inspector Shell
     └── ministry_admin → Ministry Shell
```

One login screen. One app. Each user sees only their own interface.

---

## 👥 Role Features

### 🚐 Driver
- Full-screen map showing assigned route with waypoints
- GPS streamed to backend via WebSocket every 15 m
- Violation alerts pushed instantly from server
- Status toggle: Start Shift / Go Offline
- Relocation request form (zone picker + reason)
- Real-time relocation approval/rejection feedback
- Relocation status history
- Route info: name, official fare, waypoint count

### 🧍 Passenger
- Live map: nearby buses (colour-coded on/off route)
- Zone demand circles (green=OK, orange=LOW, red=CRITICAL_LOW, blue=HIGH)
- Zone demand summary sheet
- One-tap check-in at stop (signals waiting demand to system)
- Check-out when boarding
- Violation report: plate, type, zone, description
- Demand situation report: zone, type, description

### 🛡️ Inspector
- Plate lookup tab: enter any plate → full bus info
  - Compliance score with progress bar
  - Active relocation permit (if any)
  - Recent violation history
  - Confirm or dismiss violation on the spot
- Dispatches tab: pending alerts with badge counter
  - Acknowledge dispatch
  - Complete dispatch
  - Quick plate lookup from dispatch card
- Field observation form: zone, type, plate, description

### 🏛️ Ministry Admin
- **Live Map**: all active buses, green=on_route, red=off_route
- **Zones**: supply/demand status with bus count per zone
- **Relocations**: pending requests with approve / reject (with reason)
- **Violations**: full list with manual inspector dispatch
- **Reports**: passenger violation reports, demand reports, field observations, all with mark-as-reviewed
- **Dashboard**: live stats (drivers, violations, relocations, zone snapshot, compliance report)

---

## 🔌 Real-Time (WebSocket)

| Role | Endpoint | Events Handled |
|---|---|---|
| Driver | `ws://.../ws/driver/` | `violation_alert`, `relocation_approved`, `relocation_rejected`, `relocation_recommendation` |
| Inspector | `ws://.../ws/inspector/` | `dispatch` (new dispatch notification) |
| Ministry | `ws://.../ws/dashboard/` | `bus_moved`, `violation_detected`, `zone_update`, `relocation_recommendation` |

Auto-reconnects with 3s backoff on disconnect.

---

## 🏗️ Project Structure

```
lib/
├── main.dart
├── app.dart                          # MaterialApp.router
├── core/
│   ├── api/
│   │   ├── api_client.dart           # Dio + JWT interceptor + auto-refresh
│   │   ├── api_service.dart          # Typed methods for every endpoint
│   │   └── websocket_service.dart    # WS connection + reconnect
│   ├── auth/
│   │   ├── auth_service.dart         # Login, register, token storage
│   │   └── auth_provider.dart        # Riverpod providers + AuthNotifier
│   └── models/
│       ├── driver.dart
│       ├── route.dart
│       ├── zone.dart
│       ├── violation.dart
│       ├── relocation.dart
│       ├── dispatch.dart
│       ├── bus_lookup.dart
│       └── passenger_report.dart
├── features/
│   ├── driver/
│   │   ├── screens/driver_home_screen.dart
│   │   └── services/gps_service.dart
│   ├── passenger/
│   │   └── screens/passenger_home_screen.dart
│   ├── inspector/
│   │   └── screens/inspector_home_screen.dart
│   └── ministry/
│       └── screens/ministry_screen.dart
└── routing/
    ├── app_router.dart               # GoRouter + role-based redirect
    ├── login_screen.dart
    └── register_screen.dart
```

---

## 📦 Tech Stack

| Concern | Package |
|---|---|
| Navigation | `go_router` |
| State | `flutter_riverpod` |
| HTTP | `dio` (with JWT interceptor + auto-refresh) |
| WebSocket | `web_socket_channel` |
| Token storage | `flutter_secure_storage` |
| Maps | `flutter_map` + OpenStreetMap (no API key needed) |
| GPS | `geolocator` |
| Notifications | `flutter_local_notifications` |

---

## ⚙️ Configuration

Set your backend URL in `lib/core/auth/auth_provider.dart`:

```dart
const kApiBaseUrl = 'http://10.0.2.2:8000';  // Android emulator
const kWsBaseUrl  = 'ws://10.0.2.2:8000';

// Physical device on same network:
// const kApiBaseUrl = 'http://192.168.x.x:8000';
```

---

## 🚀 Running the App

```bash
# Install dependencies
flutter pub get

# Run on connected device or emulator
flutter run

# Build APK
flutter build apk --release
```

---

## 🔗 Backend

The Django backend is in the companion repo:
[Smart-Taxi-Distribution-System](../Smart-Taxi-Distribution-System)

Start it with:
```bash
cd backend
python manage.py runserver
celery -A backend worker -l info
celery -A backend beat -l info
```

---

## 📄 License

MIT License
