import api from './client';

// ── Auth ──────────────────────────────────────────────────────────────────────
export const login = (username, password) =>
  api.post('/api/auth/login/', { username, password });

// ── Dashboard ─────────────────────────────────────────────────────────────────
export const getDashboard      = () => api.get('/api/ministry/dashboard/');
export const getLiveBuses      = () => api.get('/api/ministry/buses/live/');
export const getZones          = () => api.get('/api/ministry/zones/');
export const getViolations     = () => api.get('/api/ministry/violations/');
export const getRelocations    = () => api.get('/api/ministry/relocation/pending/');
export const getPassengerReports = () => api.get('/api/ministry/passenger-reports/');
export const getDemandReports  = () => api.get('/api/ministry/demand-reports/');
export const getObservations   = () => api.get('/api/ministry/observations/');
export const getCompliance     = () => api.get('/api/ministry/reports/compliance/');
export const getInspectors     = () => api.get('/api/inspector/list/');

// ── Actions ───────────────────────────────────────────────────────────────────
export const decideRelocation = (id, action, validHours = 4, rejectionReason = '') =>
  api.post(`/api/ministry/relocation/${id}/decide/`, { action, valid_hours: validHours, rejection_reason: rejectionReason });

export const dispatchInspector = (violationId, inspectorId) =>
  api.post(`/api/ministry/violations/${violationId}/dispatch/`, { inspector_id: inspectorId });

export const markReportReviewed = (id) =>
  api.patch(`/api/ministry/passenger-reports/${id}/review/`);

export const markObservationReviewed = (id) =>
  api.patch(`/api/ministry/observations/${id}/review/`);

// ── Routes (Ministry manages routes) ─────────────────────────────────────────
export const getRoutes         = () => api.get('/api/ministry/routes/');
export const createRoute       = (data) => api.post('/api/ministry/routes/', data);
export const updateRoute       = (id, data) => api.patch(`/api/ministry/routes/${id}/`, data);
export const deleteRoute       = (id) => api.delete(`/api/ministry/routes/${id}/`);
export const assignDriverRoute = (driverId, routeId) =>
  api.patch(`/api/ministry/drivers/${driverId}/assign-route/`, { route_id: routeId });
export const getDrivers        = () => api.get('/api/ministry/drivers/');

// ── Zones CRUD ────────────────────────────────────────────────────────────────
export const createZone = (data) => api.post('/api/ministry/zones/create/', data);
