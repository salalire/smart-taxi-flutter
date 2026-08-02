class RouteViolation {
  final int id;
  final String driverPlate;
  final String? routeName;
  final String detectedAt;
  final double latitude;
  final double longitude;
  final String status; // open | inspector_dispatched | confirmed | dismissed
  final String? inspectorBadge;
  final String notes;

  const RouteViolation({
    required this.id,
    required this.driverPlate,
    this.routeName,
    required this.detectedAt,
    required this.latitude,
    required this.longitude,
    required this.status,
    this.inspectorBadge,
    this.notes = '',
  });

  factory RouteViolation.fromJson(Map<String, dynamic> j) => RouteViolation(
        id: j['id'] as int,
        driverPlate: j['driver_plate'] as String? ?? '',
        routeName: j['route_name'] as String?,
        detectedAt: j['detected_at'] as String? ?? '',
        latitude: (j['latitude'] as num? ?? 0).toDouble(),
        longitude: (j['longitude'] as num? ?? 0).toDouble(),
        status: j['status'] as String? ?? 'open',
        inspectorBadge: j['inspector_badge'] as String?,
        notes: j['notes'] as String? ?? '',
      );

  String get shortDate =>
      detectedAt.length >= 10 ? detectedAt.substring(0, 10) : detectedAt;
}
