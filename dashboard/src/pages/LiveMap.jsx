import { useEffect, useState } from 'react';
import { MapContainer, TileLayer, Marker, Popup, Circle } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { getLiveBuses, getZones } from '../api';
import PageHeader from '../components/PageHeader';

// Fix leaflet default icon issue with Vite
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon-2x.png',
  iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-shadow.png',
});

const busIcon = (onRoute) => L.divIcon({
  className: '',
  html: `<div style="
    background:${onRoute ? '#16a34a' : '#dc2626'};
    color:#fff; border-radius:50%; width:32px; height:32px;
    display:flex; align-items:center; justify-content:center;
    font-size:16px; border:2px solid #fff;
    box-shadow:0 2px 4px rgba(0,0,0,0.3);
  ">🚐</div>`,
  iconSize: [32, 32],
  iconAnchor: [16, 16],
});

const zoneColor = (s) =>
  s === 'CRITICAL_LOW' ? '#ef4444' : s === 'LOW' ? '#f97316' : s === 'HIGH' ? '#3b82f6' : '#16a34a';

export default function LiveMap() {
  const [buses, setBuses] = useState([]);
  const [zones, setZones] = useState([]);

  const load = async () => {
    const [b, z] = await Promise.all([getLiveBuses(), getZones()]);
    setBuses(b.data);
    setZones(z.data);
  };

  useEffect(() => { load(); const t = setInterval(load, 10000); return () => clearInterval(t); }, []);

  return (
    <div style={{ padding: 32 }}>
      <PageHeader
        title="Live Map"
        subtitle={`${buses.filter(b => b.status === 'on_route').length} on route · ${buses.filter(b => b.status === 'off_route').length} off route · refreshes every 10s`}
      />

      {/* Legend */}
      <div style={{ display: 'flex', gap: 16, marginBottom: 16, flexWrap: 'wrap' }}>
        {[
          { color: '#16a34a', label: 'On Route' },
          { color: '#dc2626', label: 'Off Route' },
          { color: '#4ade8040', border: '#16a34a', label: 'Zone OK' },
          { color: '#f9731640', border: '#f97316', label: 'Zone LOW' },
          { color: '#ef444440', border: '#ef4444', label: 'Zone CRITICAL' },
          { color: '#3b82f640', border: '#3b82f6', label: 'Zone HIGH' },
        ].map(({ color, border, label }) => (
          <div key={label} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13 }}>
            <div style={{
              width: 14, height: 14, background: color,
              border: border ? `2px solid ${border}` : 'none',
              borderRadius: 3,
            }} />
            {label}
          </div>
        ))}
      </div>

      <div style={{ borderRadius: 12, overflow: 'hidden', boxShadow: '0 1px 3px rgba(0,0,0,0.12)' }}>
        <MapContainer
          center={[9.03, 38.74]}
          zoom={12}
          style={{ height: 580, width: '100%' }}
        >
          <TileLayer
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            attribution="© OpenStreetMap contributors"
          />

          {/* Zone circles */}
          {zones.map((z) => (
            <Circle
              key={z.id}
              center={[z.center_latitude, z.center_longitude]}
              radius={z.radius_km * 1000}
              pathOptions={{
                color: zoneColor(z.status || 'OK'),
                fillColor: zoneColor(z.status || 'OK'),
                fillOpacity: 0.1,
                weight: 2,
              }}
            >
              <Popup>
                <strong>{z.name}</strong><br />
                Status: {z.status || 'OK'}<br />
                Buses: {z.bus_count || 0}
              </Popup>
            </Circle>
          ))}

          {/* Bus markers */}
          {buses
            .filter((b) => b.current_latitude && b.current_longitude)
            .map((b) => (
              <Marker
                key={b.id}
                position={[b.current_latitude, b.current_longitude]}
                icon={busIcon(b.status === 'on_route')}
              >
                <Popup>
                  <strong>{b.license_plate}</strong><br />
                  Driver: {b.username}<br />
                  Status: {b.status?.replace('_', ' ')}<br />
                  Route: {b.assigned_route?.name || '—'}<br />
                  Compliance: {b.compliance_score}/100
                </Popup>
              </Marker>
            ))}
        </MapContainer>
      </div>
    </div>
  );
}
