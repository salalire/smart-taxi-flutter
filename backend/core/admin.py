from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import (
    User, Driver, Inspector, Passenger,
    Zone, ZoneThreshold, Route, RouteWaypoint,
    LocationUpdate, RouteViolation, PassengerReport, PassengerDemandReport,
    StopCheckIn, InspectorFieldObservation,
    RelocationRequest, InspectorDispatch,
)


@admin.register(User)
class CustomUserAdmin(UserAdmin):
    list_display  = ['id', 'username', 'email', 'phone', 'role', 'is_active']
    list_filter   = ['role', 'is_active']
    search_fields = ['username', 'email', 'phone']
    fieldsets     = UserAdmin.fieldsets + (
        ('Taxi System', {'fields': ('role', 'phone')}),
    )
    add_fieldsets = UserAdmin.add_fieldsets + (
        ('Taxi System', {'fields': ('role', 'phone', 'email')}),
    )


@admin.register(Driver)
class DriverAdmin(admin.ModelAdmin):
    list_display  = ['id', 'license_plate', 'user', 'assigned_route', 'status', 'compliance_score', 'last_seen']
    list_filter   = ['status']
    search_fields = ['license_plate', 'user__username']


@admin.register(Inspector)
class InspectorAdmin(admin.ModelAdmin):
    list_display  = ['id', 'badge_number', 'user', 'assigned_zone']
    search_fields = ['badge_number', 'user__username']


@admin.register(Passenger)
class PassengerAdmin(admin.ModelAdmin):
    list_display  = ['id', 'user']
    search_fields = ['user__username']


@admin.register(Zone)
class ZoneAdmin(admin.ModelAdmin):
    list_display = ['id', 'name', 'center_latitude', 'center_longitude', 'radius_km']


@admin.register(ZoneThreshold)
class ZoneThresholdAdmin(admin.ModelAdmin):
    list_display = ['id', 'zone', 'day_of_week', 'hour_start', 'hour_end', 'min_buses', 'max_buses']
    list_filter  = ['zone', 'day_of_week']


@admin.register(Route)
class RouteAdmin(admin.ModelAdmin):
    list_display = ['id', 'name', 'zone', 'official_fare', 'max_deviation_km', 'is_active']
    list_filter  = ['zone', 'is_active']


@admin.register(RouteWaypoint)
class RouteWaypointAdmin(admin.ModelAdmin):
    list_display = ['id', 'route', 'order', 'latitude', 'longitude', 'label']
    list_filter  = ['route']


@admin.register(LocationUpdate)
class LocationUpdateAdmin(admin.ModelAdmin):
    list_display = ['id', 'driver', 'latitude', 'longitude', 'is_on_route', 'timestamp']
    list_filter  = ['is_on_route', 'driver']


@admin.register(RouteViolation)
class RouteViolationAdmin(admin.ModelAdmin):
    list_display  = ['id', 'driver', 'route', 'status', 'detected_at', 'recorded_by']
    list_filter   = ['status']
    search_fields = ['driver__license_plate']


@admin.register(PassengerReport)
class PassengerReportAdmin(admin.ModelAdmin):
    list_display  = ['id', 'plate_number', 'reporter', 'report_type', 'zone', 'created_at', 'is_reviewed']
    list_filter   = ['report_type', 'is_reviewed']
    search_fields = ['plate_number']


@admin.register(RelocationRequest)
class RelocationRequestAdmin(admin.ModelAdmin):
    list_display  = ['id', 'driver', 'from_zone', 'to_zone', 'initiated_by', 'status', 'requested_at', 'valid_until']
    list_filter   = ['status', 'initiated_by']
    search_fields = ['driver__license_plate']


@admin.register(InspectorDispatch)
class InspectorDispatchAdmin(admin.ModelAdmin):
    list_display = ['id', 'inspector', 'violation', 'status', 'dispatched_at', 'responded_at']
    list_filter  = ['status']


@admin.register(PassengerDemandReport)
class PassengerDemandReportAdmin(admin.ModelAdmin):
    list_display  = ['id', 'reporter', 'zone', 'report_type', 'weight', 'created_at', 'is_processed']
    list_filter   = ['report_type', 'zone', 'is_processed']
    search_fields = ['reporter__user__username']


@admin.register(StopCheckIn)
class StopCheckInAdmin(admin.ModelAdmin):
    list_display  = ['id', 'passenger', 'zone', 'weight', 'checked_in_at', 'is_active']
    list_filter   = ['zone', 'is_active']
    search_fields = ['passenger__user__username']


@admin.register(InspectorFieldObservation)
class InspectorFieldObservationAdmin(admin.ModelAdmin):
    list_display  = ['id', 'inspector', 'zone', 'observation_type', 'plate_number', 'created_at', 'is_reviewed']
    list_filter   = ['observation_type', 'zone', 'is_reviewed']
    search_fields = ['inspector__badge_number', 'plate_number']
