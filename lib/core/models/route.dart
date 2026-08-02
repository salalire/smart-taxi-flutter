class RouteWaypoint {
  final int order;
  final double latitude;
  final double longitude;
  final String label;

  const RouteWaypoint({
    required this.order,
    required this.latitude,
    required this.longitude,
    this.label = '',
  });

  factory RouteWaypoint.fromJson(Map<String, dynamic> j) => RouteWaypoint(
        order: j['order'] as int,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        label: j['label'] as String? ?? '',
      );
}

class Route {
  final int id;
  final String name;
  final String? zoneName;
  final double officialFare;
  final double maxDeviationKm;
  final bool isActive;
  final List<RouteWaypoint> waypoints;

  const Route({
    required this.id,
    required this.name,
    this.zoneName,
    required this.officialFare,
    required this.maxDeviationKm,
    required this.isActive,
    this.waypoints = const [],
  });

  factory Route.fromJson(Map<String, dynamic> j) => Route(
        id: j['id'] as int,
        name: j['name'] as String,
        zoneName: j['zone_name'] as String?,
        officialFare: (j['official_fare'] as num? ?? 0).toDouble(),
        maxDeviationKm: (j['max_deviation_km'] as num? ?? 0.3).toDouble(),
        isActive: j['is_active'] as bool? ?? true,
        waypoints: (j['waypoints'] as List? ?? [])
            .map((w) => RouteWaypoint.fromJson(w as Map<String, dynamic>))
            .toList(),
      );
}
