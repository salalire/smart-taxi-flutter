"""
ASGI config for taxi_system project.
Handles both HTTP (Django) and WebSocket (Channels) connections.

WebSocket JWT auth: token passed as query param ?token=<jwt>
"""

import os
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.middleware import BaseMiddleware
from channels.db import database_sync_to_async

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'taxi_system.settings')

from realtime.routing import websocket_urlpatterns  # noqa: E402


class JWTAuthMiddleware(BaseMiddleware):
    """
    Authenticates WebSocket connections using a JWT token
    passed as a query parameter: ws://host/ws/dashboard/?token=<jwt>
    """

    async def __call__(self, scope, receive, send):
        from urllib.parse import parse_qs
        from django.contrib.auth.models import AnonymousUser

        query_string = scope.get('query_string', b'').decode()
        params       = parse_qs(query_string)
        token_list   = params.get('token', [])

        if token_list:
            scope['user'] = await self._get_user(token_list[0])
        else:
            scope['user'] = AnonymousUser()

        return await super().__call__(scope, receive, send)

    @database_sync_to_async
    def _get_user(self, token_str):
        from django.contrib.auth.models import AnonymousUser
        try:
            from rest_framework_simplejwt.tokens import AccessToken
            from core.models import User
            token   = AccessToken(token_str)
            user_id = token['user_id']
            return User.objects.get(id=user_id)
        except Exception:
            return AnonymousUser()


application = ProtocolTypeRouter({
    'http': get_asgi_application(),
    'websocket': JWTAuthMiddleware(
        URLRouter(websocket_urlpatterns)
    ),
})
