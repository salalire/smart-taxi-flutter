import 'route.dart';

class Driver {
  final int id;
  final String username;
  final String licensePlate;
  final String status; // on_route | off_route | relocating | offline
  final int complianceScore;
  final Route? assignedRoute;
  final double? currentLatitude;
  final double? currentLongitude;
  final String? lastSeen;

  const Driver({
    required this.id,
    required this.username,
    required this.licensePlate,
    required this.status,
    required this.complianceScore,
    this.assignedRoute,
    this.currentLatitude,
    this.currentLongitude,
    this.lastSeen,
  });

  factory Driver.fromJson(Map<String, dynamic> j) => Driver(
        id: j['id'] as int,
        username: j['username'] as String? ?? '',
        licensePlate: j['license_plate'] as String,
        status: j['status'] as String? ?? 'offline',
        complianceScore: j['compliance_score'] as int? ?? 100,
        assignedRoute: j['assigned_route'] != null
            ? Route.fromJson(j['assigned_route'] as Map<String, dynamic>)
            : null,
        currentLatitude: (j['current_latitude'] as num?)?.toDouble(),
        currentLongitude: (j['current_longitude'] as num?)?.toDouble(),
        lastSeen: j['last_seen'] as String?,
      );

  bool get isOnline => status != 'offline';
  bool get isOnRoute => status == 'on_route';
}
