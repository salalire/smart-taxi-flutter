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
  final int? zoneId;
  final String? zoneName;
  final int? destinationZoneId;
  final String? destinationZoneName;
  final double officialFare;
  final double maxDeviationKm;
  final bool isActive;
  final List<RouteWaypoint> waypoints;

  const Route({
    required this.id,
    required this.name,
    this.zoneId,
    this.zoneName,
    this.destinationZoneId,
    this.destinationZoneName,
    required this.officialFare,
    required this.maxDeviationKm,
    required this.isActive,
    this.waypoints = const [],
  });

  factory Route.fromJson(Map<String, dynamic> j) => Route(
        id: j['id'] as int,
        name: j['name'] as String,
        zoneId: j['zone'] as int?,
        zoneName: j['zone_name'] as String?,
        destinationZoneId: j['destination_zone_id'] as int?,
        destinationZoneName: j['destination_zone_name'] as String?,
        // official_fare comes as a decimal string e.g. "25.00" from DRF
        officialFare: double.tryParse(j['official_fare']?.toString() ?? '0') ?? 0.0,
        maxDeviationKm: (j['max_deviation_km'] as num? ?? 0.3).toDouble(),
        isActive: j['is_active'] as bool? ?? true,
        waypoints: (j['waypoints'] as List? ?? [])
            .map((w) => RouteWaypoint.fromJson(w as Map<String, dynamic>))
            .toList(),
      );
}
