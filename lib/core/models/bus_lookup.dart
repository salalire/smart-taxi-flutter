// What the inspector sees after scanning a plate number.
// Maps to BusLookupSerializer in the backend.
import 'violation.dart';

class BusLookup {
  final String licensePlate;
  final String username;
  final String status;
  final int complianceScore;
  final String? assignedRoute;
  final double? currentLatitude;
  final double? currentLongitude;
  final List<RouteViolation> recentViolations;
  final ActiveRelocation? activeRelocation;

  const BusLookup({
    required this.licensePlate,
    required this.username,
    required this.status,
    required this.complianceScore,
    this.assignedRoute,
    this.currentLatitude,
    this.currentLongitude,
    this.recentViolations = const [],
    this.activeRelocation,
  });

  factory BusLookup.fromJson(Map<String, dynamic> j) => BusLookup(
        licensePlate: j['license_plate'] as String,
        username: j['username'] as String? ?? '',
        status: j['status'] as String? ?? 'offline',
        complianceScore: j['compliance_score'] as int? ?? 100,
        assignedRoute: j['assigned_route'] as String?,
        currentLatitude: (j['current_latitude'] as num?)?.toDouble(),
        currentLongitude: (j['current_longitude'] as num?)?.toDouble(),
        recentViolations: (j['recent_violations'] as List? ?? [])
            .map((v) => RouteViolation.fromJson(v as Map<String, dynamic>))
            .toList(),
        activeRelocation: j['active_relocation'] != null
            ? ActiveRelocation.fromJson(
                j['active_relocation'] as Map<String, dynamic>)
            : null,
      );
}

class ActiveRelocation {
  final String toZone;
  final String validUntil;

  const ActiveRelocation({required this.toZone, required this.validUntil});

  factory ActiveRelocation.fromJson(Map<String, dynamic> j) =>
      ActiveRelocation(
        toZone: j['to_zone'] as String,
        validUntil: j['valid_until'] as String,
      );
}
