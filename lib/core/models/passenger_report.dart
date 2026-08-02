class PassengerReport {
  final int id;
  final String passengerUsername;
  final String plateNumber;
  final String reportType; // wrong_route | overcharging | overcrowding | other
  final String? zoneName;
  final String description;
  final String createdAt;
  final bool isReviewed;

  const PassengerReport({
    required this.id,
    required this.passengerUsername,
    required this.plateNumber,
    required this.reportType,
    this.zoneName,
    required this.description,
    required this.createdAt,
    required this.isReviewed,
  });

  factory PassengerReport.fromJson(Map<String, dynamic> j) => PassengerReport(
        id: j['id'] as int,
        passengerUsername: j['passenger_username'] as String? ?? '',
        plateNumber: j['plate_number'] as String? ?? '',
        reportType: j['report_type'] as String? ?? 'other',
        zoneName: j['zone_name'] as String?,
        description: j['description'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
        isReviewed: j['is_reviewed'] as bool? ?? false,
      );
}

class DemandReport {
  final int id;
  final int zoneId;
  final String zoneName;
  final String reportType;
  final String description;
  final double weight;
  final String createdAt;

  const DemandReport({
    required this.id,
    required this.zoneId,
    required this.zoneName,
    required this.reportType,
    required this.description,
    required this.weight,
    required this.createdAt,
  });

  factory DemandReport.fromJson(Map<String, dynamic> j) => DemandReport(
        id: j['id'] as int,
        zoneId: j['zone'] as int,
        zoneName: j['zone_name'] as String? ?? '',
        reportType: j['report_type'] as String? ?? '',
        description: j['description'] as String? ?? '',
        weight: (j['weight'] as num? ?? 1.0).toDouble(),
        createdAt: j['created_at'] as String? ?? '',
      );
}
