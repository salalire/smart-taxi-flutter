import 'violation.dart';

class InspectorDispatch {
  final int id;
  final String inspectorBadge;
  final RouteViolation? violation;
  final String dispatchedAt;
  final String? respondedAt;
  final String status; // sent | acknowledged | completed
  final bool autoDispatched;

  const InspectorDispatch({
    required this.id,
    required this.inspectorBadge,
    this.violation,
    required this.dispatchedAt,
    this.respondedAt,
    required this.status,
    required this.autoDispatched,
  });

  factory InspectorDispatch.fromJson(Map<String, dynamic> j) =>
      InspectorDispatch(
        id: j['id'] as int,
        inspectorBadge: j['inspector_badge'] as String? ?? '',
        violation: j['violation'] != null
            ? RouteViolation.fromJson(j['violation'] as Map<String, dynamic>)
            : null,
        dispatchedAt: j['dispatched_at'] as String? ?? '',
        respondedAt: j['responded_at'] as String?,
        status: j['status'] as String? ?? 'sent',
        autoDispatched: j['auto_dispatched'] as bool? ?? false,
      );
}
