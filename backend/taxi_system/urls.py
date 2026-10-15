"""
Root URL configuration for taxi_system.
"""

from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),

    # All API routes live under /api/
    path('api/', include('core.urls')),
]
