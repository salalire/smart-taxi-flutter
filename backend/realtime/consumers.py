"""
WebSocket consumers for real-time communication.
"""

import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async


class DriverConsumer(AsyncWebsocketConsumer):

    async def connect(self):
        self.user = self.scope.get('user')
        if not self.user or not self.user.is_authenticated:
            await self.close()
            return
        self.group_name = f'driver_{self.user.id}'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        if hasattr(self, 'group_name'):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)
        if self.user and self.user.is_authenticated:
            await self._set_driver_offline()

    async def receive(self, text_data):
        try:
            data = json.loads(text_data)
        except json.JSONDecodeError:
            await self.send(text_data=json.dumps({'type': 'error', 'message': 'Invalid JSON.'}))
            return

        msg_type = data.get('type')
        if msg_type == 'location_update':
            lat = data.get('lat')
            lng = data.get('lng')
            if lat is None or lng is None:
                await self.send(text_data=json.dumps({'type': 'error', 'message': 'lat and lng required.'}))
                return
            await self._handle_location_update(lat, lng)

    async def violation_alert(self, event):
        await self.send(text_data=json.dumps({
            'type':    'violation_alert',
            'message': event['message'],
        }))

    async def relocation_approved(self, event):
        await self.send(text_data=json.dumps({
            'type':        'relocation_approved',
            'to_zone':     event['to_zone'],
            'valid_until': event['valid_until'],
        }))

    async def relocation_rejected(self, event):
        await self.send(text_data=json.dumps({
            'type':   'relocation_rejected',
            'reason': event['reason'],
        }))

    async def relocation_recommendation(self, event):
        await self.send(text_data=json.dumps({
            'type':    'relocation_recommendation',
            'to_zone': event['to_zone'],
            'reason':  event['reason'],
        }))

    @database_sync_to_async
    def _handle_location_update(self, lat, lng):
        from core.models import Driver
        from asgiref.sync import async_to_sync
        from channels.layers import get_channel_layer

        try:
            driver          = self.user.driver_profile
            location_update = driver.update_location(lat, lng)
            channel_layer   = get_channel_layer()

            if channel_layer:
                try:
                    async_to_sync(channel_layer.group_send)(
                        'dashboard',
                        {
                            'type':      'bus_moved',
                            'driver_id': driver.id,
                            'plate':     driver.license_plate,
                            'lat':       lat,
                            'lng':       lng,
                            'status':    driver.status,
                            'on_route':  location_update.is_on_route,
                        }
                    )
                except Exception:
                    pass

                if not location_update.is_on_route:
                    try:
                        async_to_sync(channel_layer.group_send)(
                            f'driver_{self.user.id}',
                            {
                                'type':    'violation_alert',
                                'message': 'You have left your assigned route. Please return immediately.',
                            }
                        )
                    except Exception:
                        pass

        except Driver.DoesNotExist:
            pass

    @database_sync_to_async
    def _set_driver_offline(self):
        from core.models import Driver
        try:
            driver = self.user.driver_profile
            driver.status = Driver.STATUS_OFFLINE
            driver.save(update_fields=['status'])
        except Driver.DoesNotExist:
            pass


class InspectorConsumer(AsyncWebsocketConsumer):

    async def connect(self):
        self.user = self.scope.get('user')
        if not self.user or not self.user.is_authenticated:
            await self.close()
            return
        self.group_name = f'inspector_{self.user.id}'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        if hasattr(self, 'group_name'):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive(self, text_data):
        pass

    async def dispatch_alert(self, event):
        await self.send(text_data=json.dumps({
            'type':         'dispatch',
            'dispatch_id':  event['dispatch_id'],
            'violation_id': event['violation_id'],
            'plate':        event['plate'],
            'lat':          event['lat'],
            'lng':          event['lng'],
        }))


class DashboardConsumer(AsyncWebsocketConsumer):

    async def connect(self):
        self.user = self.scope.get('user')
        if not self.user or not self.user.is_authenticated:
            await self.close()
            return
        await self.channel_layer.group_add('dashboard', self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard('dashboard', self.channel_name)

    async def receive(self, text_data):
        pass

    async def bus_moved(self, event):
        await self.send(text_data=json.dumps({
            'type':      'bus_moved',
            'driver_id': event['driver_id'],
            'plate':     event['plate'],
            'lat':       event['lat'],
            'lng':       event['lng'],
            'status':    event['status'],
            'on_route':  event['on_route'],
        }))

    async def violation_detected(self, event):
        await self.send(text_data=json.dumps({
            'type':         'violation_detected',
            'violation_id': event['violation_id'],
            'plate':        event['plate'],
            'lat':          event['lat'],
            'lng':          event['lng'],
        }))

    async def zone_update(self, event):
        await self.send(text_data=json.dumps({
            'type':      'zone_update',
            'zone_id':   event['zone_id'],
            'zone_name': event['zone_name'],
            'status':    event['status'],
            'bus_count': event['bus_count'],
        }))

    async def relocation_recommendation(self, event):
        await self.send(text_data=json.dumps({
            'type':         'relocation_recommendation',
            'zone':         event['zone'],
            'zone_status':  event['zone_status'],
            'driver_plate': event['driver_plate'],
            'distance_km':  event.get('distance_km'),
        }))
