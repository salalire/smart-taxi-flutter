import { useEffect, useState } from 'react';
import { getDrivers, getRoutes, assignDriverRoute } from '../api';
import PageHeader from '../components/PageHeader';

const statusColor = (s) =>
  s === 'on_route' ? '#16a34a' : s === 'off_route' ? '#dc2626' :
  s === 'relocating' ? '#3b82f6' : '#94a3b8';

export default function Drivers() {
  const [drivers, setDrivers] = useState([]);
  const [routes, setRoutes]   = useState([]);
  const [loading, setLoading] = useState(true);
  const [assigning, setAssigning] = useState(null);

  const load = async () => {
    const [d, r] = await Promise.all([getDrivers(), getRoutes()]);
    setDrivers(d.data);
    setRoutes(r.data);
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const assign = async (driverId, routeId) => {
    setAssigning(driverId);
    try {
      await assignDriverRoute(driverId, routeId ? parseInt(routeId) : null);
      await load();
    } catch (e) {
      alert('Error: ' + (e.response?.data?.error || e.message));
    } finally {
      setAssigning(null);
    }
  };

  if (loading) return <div style={{ padding: 32, color: '#64748b' }}>Loading...</div>;

  return (
    <div style={{ padding: 32 }}>
      <PageHeader title="Drivers" subtitle={`${drivers.length} registered drivers`} />

      <div style={{ background: '#fff', borderRadius: 12, boxShadow: '0 1px 3px rgba(0,0,0,0.08)', overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ background: '#f8fafc', borderBottom: '2px solid #e2e8f0' }}>
              {['Driver', 'Plate', 'Status', 'Compliance', 'Assigned Route', 'Change Route'].map(h => (
                <th key={h} style={{ padding: '12px 16px', textAlign: 'left', fontSize: 13, fontWeight: 600, color: '#64748b' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {drivers.map((d) => {
              const score = d.compliance_score ?? 100;
              const scoreColor = score >= 80 ? '#16a34a' : score >= 60 ? '#f97316' : '#dc2626';
              return (
                <tr key={d.id} style={{ borderBottom: '1px solid #f1f5f9' }}>
                  <td style={{ padding: '12px 16px', fontWeight: 600, color: '#1e293b' }}>{d.username}</td>
                  <td style={{ padding: '12px 16px', fontSize: 13 }}>{d.license_plate}</td>
                  <td style={{ padding: '12px 16px' }}>
                    <span style={{
                      padding: '3px 10px', borderRadius: 20, fontSize: 12, fontWeight: 600,
                      background: `${statusColor(d.status)}15`, color: statusColor(d.status),
                    }}>
                      {d.status?.replace(/_/g, ' ')}
                    </span>
                  </td>
                  <td style={{ padding: '12px 16px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <div style={{ flex: 1, background: '#f1f5f9', borderRadius: 4, height: 6, minWidth: 60 }}>
                        <div style={{ width: `${score}%`, background: scoreColor, height: '100%', borderRadius: 4 }} />
                      </div>
                      <span style={{ fontSize: 12, fontWeight: 600, color: scoreColor }}>{score}</span>
                    </div>
                  </td>
                  <td style={{ padding: '12px 16px', fontSize: 13, color: '#64748b' }}>
                    {d.assigned_route?.name || <span style={{ color: '#f97316' }}>No route</span>}
                  </td>
                  <td style={{ padding: '12px 16px' }}>
                    <select
                      value={d.assigned_route?.id || ''}
                      onChange={(e) => assign(d.id, e.target.value)}
                      disabled={assigning === d.id}
                      style={{
                        padding: '6px 10px', border: '1.5px solid #e2e8f0', borderRadius: 6,
                        fontSize: 13, cursor: 'pointer', minWidth: 160,
                      }}
                    >
                      <option value="">No route</option>
                      {routes.map(r => <option key={r.id} value={r.id}>{r.name}</option>)}
                    </select>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
        {drivers.length === 0 && <div style={{ padding: 40, textAlign: 'center', color: '#94a3b8' }}>No drivers found.</div>}
      </div>
    </div>
  );
}
