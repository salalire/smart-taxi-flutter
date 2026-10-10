class Zone {
  final int id;
  final String name;
  final double centerLatitude;
  final double centerLongitude;
  final double radiusKm;
  final String status; // OK | LOW | CRITICAL_LOW | HIGH
  final int busCount;
  final int demandCount;

  const Zone({
    required this.id,
    required this.name,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.radiusKm,
    this.status = 'OK',
    this.busCount = 0,
    this.demandCount = 0,
  });

  factory Zone.fromJson(Map<String, dynamic> j) => Zone(
        id: j['id'] as int,
        name: j['name'] as String,
        // Backend always sends center_latitude/center_longitude.
        // center_lat/center_lng are accepted as fallbacks for the
        // zone_demand_summary endpoint which uses different key names.
        centerLatitude: ((j['center_latitude'] ?? j['center_lat']) as num? ?? 0.0).toDouble(),
        centerLongitude: ((j['center_longitude'] ?? j['center_lng']) as num? ?? 0.0).toDouble(),
        radiusKm: (j['radius_km'] as num? ?? 2.0).toDouble(),
        status: j['status'] as String? ?? 'OK',
        busCount: j['bus_count'] as int? ?? 0,
        demandCount: j['demand_count'] as int? ?? 0,
      );
}
