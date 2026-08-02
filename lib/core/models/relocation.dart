class RelocationRequest {
  final int id;
  final String driverPlate;
  final String? fromZoneName;
  final String? toZoneName;
  final String reason;
  final String initiatedBy; // system | driver
  final String status; // pending | approved | rejected | expired
  final String requestedAt;
  final String? decidedAt;
  final String? validUntil;
  final String? approvedByUsername;
  final String? rejectionReason;

  const RelocationRequest({
    required this.id,
    required this.driverPlate,
    this.fromZoneName,
    this.toZoneName,
    required this.reason,
    required this.initiatedBy,
    required this.status,
    required this.requestedAt,
    this.decidedAt,
    this.validUntil,
    this.approvedByUsername,
    this.rejectionReason,
  });

  factory RelocationRequest.fromJson(Map<String, dynamic> j) =>
      RelocationRequest(
        id: j['id'] as int,
        driverPlate: j['driver_plate'] as String? ?? '',
        fromZoneName: j['from_zone_name'] as String?,
        toZoneName: j['to_zone_name'] as String?,
        reason: j['reason'] as String? ?? '',
        initiatedBy: j['initiated_by'] as String? ?? 'driver',
        status: j['status'] as String? ?? 'pending',
        requestedAt: j['requested_at'] as String? ?? '',
        decidedAt: j['decided_at'] as String?,
        validUntil: j['valid_until'] as String?,
        approvedByUsername: j['approved_by_username'] as String?,
        rejectionReason: j['rejection_reason'] as String?,
      );

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
}
