import { useEffect, useState } from 'react';
import { getDashboard } from '../api';
import StatCard from '../components/StatCard';
import PageHeader from '../components/PageHeader';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts';

export default function Dashboard() {
  const [data, setData]     = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError]   = useState('');

  const load = async () => {
    try {
      const res = await getDashboard();
      setData(res.data);
    } catch {
      setError('Failed to load dashboard.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); const t = setInterval(load, 15000); return () => clearInterval(t); }, []);

  if (loading) return <div style={{ padding: 32, color: '#64748b' }}>Loading...</div>;
  if (error)   return <div style={{ padding: 32, color: '#ef4444' }}>{error}</div>;

  const d = data.drivers    || {};
  const v = data.violations || {};
  const r = data.relocations || {};
  const zones = data.zones  || [];

  const driverChart = [
    { name: 'On Route',   value: d.on_route  || 0, color: '#4ade80' },
    { name: 'Off Route',  value: d.off_route || 0, color: '#f87171' },
    { name: 'Relocating', value: d.relocating || 0, color: '#60a5fa' },
    { name: 'Offline',    value: d.offline   || 0, color: '#94a3b8' },
  ];

  const zoneStatusColor = (s) =>
    s === 'CRITICAL_LOW' ? '#ef4444' : s === 'LOW' ? '#f97316' : s === 'HIGH' ? '#3b82f6' : '#4ade80';

  return (
    <div style={{ padding: 32 }}>
      <PageHeader title="Dashboard" subtitle="Live system overview — refreshes every 15s" />

      {/* Driver stats */}
      <h2 style={{ fontSize: 15, fontWeight: 700, color: '#64748b', margin: '0 0 12px', textTransform: 'uppercase', letterSpacing: 1 }}>
        Drivers
      </h2>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(160px, 1fr))', gap: 16, marginBottom: 32 }}>
        <StatCard title="Total"      value={d.total}     icon="🚐" color="#6366f1" />
        <StatCard title="On Route"   value={d.on_route}  icon="🟢" color="#4ade80" />
        <StatCard title="Off Route"  value={d.off_route} icon="🔴" color="#f87171" />
        <StatCard title="Relocating" value={d.relocating} icon="🔄" color="#60a5fa" />
        <StatCard title="Offline"    value={d.offline}   icon="⚫" color="#94a3b8" />
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 24, marginBottom: 32 }}>
        {/* Driver chart */}
        <div style={{ background: '#fff', borderRadius: 12, padding: 24, boxShadow: '0 1px 3px rgba(0,0,0,0.08)' }}>
          <h3 style={{ margin: '0 0 16px', fontSize: 15, color: '#1e293b' }}>Driver Status Distribution</h3>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={driverChart}>
              <XAxis dataKey="name" tick={{ fontSize: 12 }} />
              <YAxis tick={{ fontSize: 12 }} />
              <Tooltip />
              <Bar dataKey="value" radius={[4, 4, 0, 0]}>
                {driverChart.map((entry, i) => <Cell key={i} fill={entry.color} />)}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>

        {/* Violations & Relocations */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div style={{ background: '#fff', borderRadius: 12, padding: 20, boxShadow: '0 1px 3px rgba(0,0,0,0.08)' }}>
            <h3 style={{ margin: '0 0 12px', fontSize: 15, color: '#1e293b' }}>⚠️ Violations</h3>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
              {[['Open', v.open, '#f97316'], ['Dispatched', v.dispatched, '#3b82f6'], ['Confirmed', v.confirmed, '#ef4444'], ['Dismissed', v.dismissed, '#94a3b8']].map(([k, val, c]) => (
                <div key={k} style={{ textAlign: 'center', padding: '10px', background: '#f8fafc', borderRadius: 8 }}>
                  <div style={{ fontSize: 22, fontWeight: 700, color: c }}>{val ?? 0}</div>
                  <div style={{ fontSize: 12, color: '#64748b' }}>{k}</div>
                </div>
              ))}
            </div>
          </div>
          <div style={{ background: '#fff', borderRadius: 12, padding: 20, boxShadow: '0 1px 3px rgba(0,0,0,0.08)' }}>
            <h3 style={{ margin: '0 0 12px', fontSize: 15, color: '#1e293b' }}>🔄 Relocations</h3>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
              {[['Pending', r.pending, '#f97316'], ['Approved', r.approved, '#4ade80'], ['Rejected', r.rejected, '#ef4444']].map(([k, val, c]) => (
                <div key={k} style={{ textAlign: 'center', padding: '10px', background: '#f8fafc', borderRadius: 8 }}>
                  <div style={{ fontSize: 22, fontWeight: 700, color: c }}>{val ?? 0}</div>
                  <div style={{ fontSize: 12, color: '#64748b' }}>{k}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Zone snapshot */}
      <h2 style={{ fontSize: 15, fontWeight: 700, color: '#64748b', margin: '0 0 12px', textTransform: 'uppercase', letterSpacing: 1 }}>
        Zone Snapshot
      </h2>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: 16 }}>
        {zones.map((z) => (
          <div key={z.id} style={{
            background: '#fff', borderRadius: 12, padding: 20,
            boxShadow: '0 1px 3px rgba(0,0,0,0.08)',
            borderLeft: `4px solid ${zoneStatusColor(z.status)}`,
          }}>
            <div style={{ fontWeight: 700, fontSize: 15, color: '#1e293b' }}>{z.name}</div>
            <div style={{ fontSize: 13, color: '#64748b', marginTop: 4 }}>{z.bus_count} bus{z.bus_count !== 1 ? 'es' : ''}</div>
            <div style={{
              display: 'inline-block', marginTop: 8, padding: '2px 10px',
              background: `${zoneStatusColor(z.status)}20`,
              color: zoneStatusColor(z.status),
              borderRadius: 20, fontSize: 12, fontWeight: 600,
            }}>
              {z.status}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
