"""
URL patterns — all prefixed with /api/ from root urls.py
"""

from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView
from . import views

urlpatterns = [
    # Auth
    path('auth/register/',  views.register,            name='auth-register'),
    path('auth/login/',     views.LoginView.as_view(),  name='auth-login'),
    path('auth/refresh/',   TokenRefreshView.as_view(), name='auth-refresh'),

    # Driver
    path('driver/routes/',                              views.route_list,                name='route-list'),
    path('driver/location/',                    views.driver_update_location,    name='driver-location'),
    path('driver/route/',                       views.driver_my_route,           name='driver-route'),
    path('driver/status/',                      views.driver_update_status,      name='driver-status'),
    path('driver/relocation/request/',          views.driver_request_relocation, name='driver-relocation-request'),
    path('driver/relocation/status/',           views.driver_relocation_status,  name='driver-relocation-status'),

    # Simple zone list for mobile app dropdowns
    path('zones/list/',     views.zone_simple_list,    name='zone-simple-list'),

    # Passenger
    path('buses/nearby/',           views.nearby_buses,            name='buses-nearby'),
    path('zones/demand/',           views.zone_demand_summary,     name='zone-demand-summary'),
    path('violations/report/',      views.submit_passenger_report, name='passenger-report'),
    path('demand/report/',          views.submit_demand_report,    name='demand-report'),
    path('stop/checkin/',           views.stop_checkin,            name='stop-checkin'),
    path('stop/checkout/',          views.stop_checkout,           name='stop-checkout'),

    # Inspector
    path('inspector/bus/<str:plate_number>/',               views.inspector_bus_lookup,        name='inspector-bus-lookup'),
    path('inspector/violations/record/',                    views.inspector_record_violation,  name='inspector-record-violation'),
    path('inspector/dispatches/',                           views.inspector_dispatches,        name='inspector-dispatches'),
    path('inspector/dispatches/<int:dispatch_id>/respond/', views.inspector_respond_dispatch,  name='inspector-dispatch-respond'),
    path('inspector/observations/',                         views.inspector_field_observation, name='inspector-observation'),
    path('inspector/list/',                                 views.inspector_list,              name='inspector-list'),

    # Ministry
    path('ministry/buses/live/',                          views.ministry_live_buses,                  name='ministry-live-buses'),
    path('ministry/violations/',                          views.ministry_violations,                  name='ministry-violations'),
    path('ministry/violations/<int:violation_id>/dispatch/', views.ministry_dispatch_inspector,       name='ministry-dispatch'),
    path('ministry/zones/',                               views.ministry_zones,                       name='ministry-zones'),
    path('ministry/relocation/pending/',                  views.ministry_pending_relocations,         name='ministry-relocations-pending'),
    path('ministry/relocation/<int:relocation_id>/decide/', views.ministry_decide_relocation,         name='ministry-relocation-decide'),
    path('ministry/reports/compliance/',                  views.ministry_compliance_report,           name='ministry-compliance-report'),
    path('ministry/observations/',                        views.ministry_observations,                name='ministry-observations'),
    path('ministry/observations/<int:observation_id>/review/', views.ministry_mark_observation_reviewed, name='ministry-observation-review'),
    path('ministry/passenger-reports/',                   views.ministry_passenger_reports,           name='ministry-passenger-reports'),
    path('ministry/passenger-reports/<int:report_id>/review/', views.ministry_mark_report_reviewed,   name='ministry-report-review'),
    path('ministry/demand-reports/',                      views.ministry_demand_reports,              name='ministry-demand-reports'),
    path('ministry/dashboard/',                           views.ministry_dashboard,                   name='ministry-dashboard'),

    # Ministry — Route & Driver management
    path('ministry/routes/',                              views.ministry_routes,                      name='ministry-routes'),
    path('ministry/routes/<int:route_id>/',               views.ministry_route_detail,                name='ministry-route-detail'),
    path('ministry/drivers/',                             views.ministry_drivers,                     name='ministry-drivers'),
    path('ministry/drivers/<int:driver_id>/assign-route/', views.ministry_assign_route,               name='ministry-assign-route'),
]
