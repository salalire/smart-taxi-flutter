import { useEffect, useState } from 'react';
import { getZones } from '../api';
import PageHeader from '../components/PageHeader';

const statusColor = (s) =>
  s === 'CRITICAL_LOW' ? '#ef4444' : s === 'LOW' ? '#f97316' : s === 'HIGH' ? '#3b82f6' : '#16a34a';

export default function Zones() {
  const [zones, setZones] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getZones().then(r => { setZones(r.data); setLoading(false); });
    const t = setInterval(() => getZones().then(r => setZones(r.data)), 15000);
    return () => clearInterval(t);
  }, []);

  if (loading) return <div style={{ padding: 32, color: '#64748b' }}>Loading...</div>;

  return (
    <div style={{ padding: 32 }}>
      <PageHeader title="Zones" subtitle="Supply and demand status per zone — refreshes every 15s" />

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: 20 }}>
        {zones.map((z) => {
          const color = statusColor(z.status || 'OK');
          return (
            <div key={z.id} style={{
              background: '#fff', borderRadius: 14, padding: 24,
              boxShadow: '0 1px 3px rgba(0,0,0,0.08)',
              borderTop: `4px solid ${color}`,
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                <h3 style={{ margin: 0, fontSize: 18, fontWeight: 700, color: '#1e293b' }}>{z.name}</h3>
                <span style={{
                  padding: '4px 12px', borderRadius: 20, fontSize: 12, fontWeight: 700,
                  background: `${color}15`, color,
                }}>{z.status || 'OK'}</span>
              </div>

              <div style={{ marginTop: 16, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                <div style={{ background: '#f8fafc', borderRadius: 8, padding: '12px 14px' }}>
                  <div style={{ fontSize: 24, fontWeight: 700, color: '#1e293b' }}>{z.bus_count ?? 0}</div>
                  <div style={{ fontSize: 12, color: '#64748b' }}>Active Buses</div>
                </div>
                <div style={{ background: '#f8fafc', borderRadius: 8, padding: '12px 14px' }}>
                  <div style={{ fontSize: 24, fontWeight: 700, color: '#1e293b' }}>{z.demand_count ?? 0}</div>
                  <div style={{ fontSize: 12, color: '#64748b' }}>Demand Signals</div>
                </div>
              </div>

              <div style={{ marginTop: 14, fontSize: 12, color: '#94a3b8' }}>
                Center: {z.center_latitude?.toFixed(4)}, {z.center_longitude?.toFixed(4)} · r={z.radius_km}km
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
