from django.urls import path
from . import consumers

websocket_urlpatterns = [
    path('ws/driver/',    consumers.DriverConsumer.as_asgi()),
    path('ws/inspector/', consumers.InspectorConsumer.as_asgi()),
    path('ws/dashboard/', consumers.DashboardConsumer.as_asgi()),
]
