// Typed API service layer.
// One method per backend endpoint — every screen imports this instead of
// calling ApiClient.get/post directly. Makes the business logic easy to follow
// and all endpoint paths live in one place.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../models/driver.dart';
import '../models/route.dart';
import '../models/zone.dart';
import '../models/relocation.dart';
import '../models/violation.dart';
import '../models/dispatch.dart';
import '../models/bus_lookup.dart';
import '../models/passenger_report.dart';
import 'api_client.dart';

// ─── Provider ────────────────────────────────────────────────────────────────

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(ref.watch(apiClientProvider));
});

// ─── Service ─────────────────────────────────────────────────────────────────

class ApiService {
  final ApiClient _c;
  ApiService(this._c);

  // ── Auth ──────────────────────────────────────────────────────────────────
  // Handled by AuthService — not duplicated here.

  // ── Zones ─────────────────────────────────────────────────────────────────

  /// Simple list of {id, name} — used in dropdowns.
  Future<List<Map<String, dynamic>>> getZonesList() async {
    final r = await _c.get('/api/zones/list/');
    return List<Map<String, dynamic>>.from(r.data as List);
  }

  /// Full zone demand summary for the passenger map.
  Future<List<Zone>> getZoneDemand() async {
    final r = await _c.get('/api/zones/demand/');
    return (r.data as List)
        .map((j) => Zone.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  // ── Driver ────────────────────────────────────────────────────────────────

  Future<Route> getMyRoute() async {
    final r = await _c.get('/api/driver/route/');
    return Route.fromJson(r.data as Map<String, dynamic>);
  }

  /// status must be 'on_route' or 'offline'
  Future<void> updateDriverStatus(String status) async {
    await _c.patch('/api/driver/status/', data: {'status': status});
  }

  /// REST fallback for GPS when WebSocket is unavailable.
  Future<Map<String, dynamic>> updateDriverLocation(
      double lat, double lng) async {
    final r = await _c
        .post('/api/driver/location/', data: {'lat': lat, 'lng': lng});
    return r.data as Map<String, dynamic>;
  }

  Future<void> requestRelocation({
    required int toZoneId,
    required String reason,
  }) async {
    await _c.post('/api/driver/relocation/request/',
        data: {'to_zone': toZoneId, 'reason': reason});
  }

  Future<RelocationRequest?> getRelocationStatus() async {
    final r = await _c.get('/api/driver/relocation/status/');
    if (r.data is Map && (r.data as Map).containsKey('id')) {
      return RelocationRequest.fromJson(r.data as Map<String, dynamic>);
    }
    return null;
  }

  // ── Passenger ─────────────────────────────────────────────────────────────

  Future<List<Driver>> getNearbyBuses(
      double lat, double lng, double radiusKm) async {
    final r = await _c.get('/api/buses/nearby/', queryParameters: {
      'lat': lat,
      'lng': lng,
      'radius_km': radiusKm,
    });
    return (r.data as List)
        .map((j) => Driver.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> submitPassengerReport({
    required String plateNumber,
    required String reportType,
    int? zoneId,
    String description = '',
    double? reporterLat,
    double? reporterLng,
  }) async {
    await _c.post('/api/violations/report/', data: {
      'plate_number': plateNumber,
      'report_type': reportType,
      if (zoneId != null) 'zone': zoneId,
      'description': description,
      if (reporterLat != null) 'reporter_latitude': reporterLat,
      if (reporterLng != null) 'reporter_longitude': reporterLng,
    });
  }

  Future<void> submitDemandReport({
    required int zoneId,
    required String reportType,
    required double lat,
    required double lng,
    String description = '',
  }) async {
    await _c.post('/api/demand/report/', data: {
      'zone': zoneId,
      'report_type': reportType,
      'reporter_latitude': lat,
      'reporter_longitude': lng,
      'description': description,
    });
  }

  Future<Map<String, dynamic>> stopCheckIn({
    required int zoneId,
    required double lat,
    required double lng,
  }) async {
    final r = await _c.post('/api/stop/checkin/', data: {
      'zone': zoneId,
      'latitude': lat,
      'longitude': lng,
    });
    return r.data as Map<String, dynamic>;
  }

  Future<void> stopCheckOut() async {
    await _c.post('/api/stop/checkout/');
  }

  // ── Inspector ─────────────────────────────────────────────────────────────

  Future<BusLookup> busLookup(String plateNumber) async {
    final r = await _c.get('/api/inspector/bus/$plateNumber/');
    return BusLookup.fromJson(r.data as Map<String, dynamic>);
  }

  /// action: 'confirm' | 'dismiss'
  Future<void> recordViolation({
    required String plateNumber,
    required String action,
    String notes = '',
  }) async {
    await _c.post('/api/inspector/violations/record/', data: {
      'plate_number': plateNumber,
      'action': action,
      'notes': notes,
    });
  }

  Future<List<InspectorDispatch>> getMyDispatches() async {
    final r = await _c.get('/api/inspector/dispatches/');
    return (r.data as List)
        .map((j) => InspectorDispatch.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// action: 'acknowledge' | 'complete'
  Future<void> respondToDispatch(int dispatchId, String action) async {
    await _c.patch('/api/inspector/dispatches/$dispatchId/respond/',
        data: {'action': action});
  }

  Future<void> submitFieldObservation({
    required int zoneId,
    required String observationType,
    required double lat,
    required double lng,
    String plateNumber = '',
    String description = '',
  }) async {
    await _c.post('/api/inspector/observations/', data: {
      'zone': zoneId,
      'observation_type': observationType,
      'plate_number': plateNumber,
      'latitude': lat,
      'longitude': lng,
      'description': description,
    });
  }

  // ── Ministry ──────────────────────────────────────────────────────────────

  Future<List<Driver>> getLiveBuses() async {
    final r = await _c.get('/api/ministry/buses/live/');
    return (r.data as List)
        .map((j) => Driver.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<RouteViolation>> getViolations({
    String? status,
    int? page,
  }) async {
    final r = await _c.get('/api/ministry/violations/', queryParameters: {
      if (status != null) 'status': status,
      if (page != null) 'page': page,
    });
    // Handle both paginated {results:[]} and plain list responses
    final raw = r.data is Map ? (r.data['results'] ?? r.data) : r.data;
    return (raw as List)
        .map((j) => RouteViolation.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Dispatch an inspector to a violation.
  Future<void> dispatchInspector(int violationId) async {
    await _c.post('/api/ministry/violations/$violationId/dispatch/');
  }

  Future<List<Zone>> getMinistryZones() async {
    final r = await _c.get('/api/ministry/zones/');
    return (r.data as List)
        .map((j) => Zone.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<RelocationRequest>> getPendingRelocations() async {
    final r = await _c.get('/api/ministry/relocation/pending/');
    return (r.data as List)
        .map((j) => RelocationRequest.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// action: 'approve' | 'reject'
  Future<void> decideRelocation({
    required int relocationId,
    required String action,
    int validHours = 4,
    String rejectionReason = '',
  }) async {
    await _c.post('/api/ministry/relocation/$relocationId/decide/', data: {
      'action': action,
      'valid_hours': validHours,
      if (rejectionReason.isNotEmpty) 'rejection_reason': rejectionReason,
    });
  }

  Future<List<PassengerReport>> getPassengerReports({bool? reviewed}) async {
    final r = await _c.get('/api/ministry/passenger-reports/',
        queryParameters: {if (reviewed != null) 'reviewed': reviewed});
    final raw = r.data is Map ? (r.data['results'] ?? r.data) : r.data;
    return (raw as List)
        .map((j) => PassengerReport.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> markPassengerReportReviewed(int reportId) async {
    await _c.patch('/api/ministry/passenger-reports/$reportId/review/');
  }

  Future<List<DemandReport>> getDemandReports() async {
    final r = await _c.get('/api/ministry/demand-reports/');
    final raw = r.data is Map ? (r.data['results'] ?? r.data) : r.data;
    return (raw as List)
        .map((j) => DemandReport.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getDashboard() async {
    final r = await _c.get('/api/ministry/dashboard/');
    return r.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getComplianceReport() async {
    final r = await _c.get('/api/ministry/reports/compliance/');
    final raw = r.data is Map ? (r.data['results'] ?? r.data) : r.data;
    return List<Map<String, dynamic>>.from(raw as List);
  }
}
