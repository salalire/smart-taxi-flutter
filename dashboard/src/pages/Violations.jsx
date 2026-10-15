import { useEffect, useState } from 'react';
import { getViolations, dispatchInspector, getInspectors } from '../api';
import PageHeader from '../components/PageHeader';

const statusColor = (s) =>
  s === 'confirmed' ? '#ef4444' : s === 'dismissed' ? '#94a3b8' :
  s === 'inspector_dispatched' ? '#3b82f6' : '#f97316';

export default function Violations() {
  const [violations, setViolations] = useState([]);
  const [inspectors, setInspectors] = useState([]);
  const [loading, setLoading]   = useState(true);
  const [dispatching, setDispatching] = useState(null);

  const load = async () => {
    const [v, i] = await Promise.all([getViolations(), getInspectors()]);
    setViolations(v.data);
    setInspectors(i.data);
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const handleDispatch = async (violationId, inspectorId) => {
    setDispatching(violationId);
    try {
      await dispatchInspector(violationId, inspectorId);
      await load();
    } catch (e) {
      alert('Error: ' + (e.response?.data?.error || e.message));
    } finally {
      setDispatching(null);
    }
  };

  if (loading) return <div style={{ padding: 32, color: '#64748b' }}>Loading...</div>;

  return (
    <div style={{ padding: 32 }}>
      <PageHeader title="Violations" subtitle={`${violations.length} total violations`} />

      <div style={{ background: '#fff', borderRadius: 12, boxShadow: '0 1px 3px rgba(0,0,0,0.08)', overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ background: '#f8fafc', borderBottom: '2px solid #e2e8f0' }}>
              {['ID', 'Plate', 'Route', 'Detected', 'Status', 'Inspector', 'Action'].map(h => (
                <th key={h} style={{ padding: '12px 16px', textAlign: 'left', fontSize: 13, fontWeight: 600, color: '#64748b' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {violations.map((v) => (
              <tr key={v.id} style={{ borderBottom: '1px solid #f1f5f9' }}>
                <td style={{ padding: '12px 16px', fontSize: 13, color: '#94a3b8' }}>#{v.id}</td>
                <td style={{ padding: '12px 16px', fontWeight: 700, color: '#1e293b' }}>{v.driver_plate}</td>
                <td style={{ padding: '12px 16px', fontSize: 13, color: '#64748b' }}>{v.route_name || '—'}</td>
                <td style={{ padding: '12px 16px', fontSize: 13, color: '#64748b' }}>{v.detected_at?.substring(0, 10)}</td>
                <td style={{ padding: '12px 16px' }}>
                  <span style={{
                    padding: '3px 10px', borderRadius: 20, fontSize: 12, fontWeight: 600,
                    background: `${statusColor(v.status)}20`, color: statusColor(v.status),
                  }}>
                    {v.status?.replace(/_/g, ' ')}
                  </span>
                </td>
                <td style={{ padding: '12px 16px', fontSize: 13, color: '#64748b' }}>{v.inspector_badge || '—'}</td>
                <td style={{ padding: '12px 16px' }}>
                  {v.status === 'open' && (
                    <select
                      onChange={(e) => e.target.value && handleDispatch(v.id, parseInt(e.target.value))}
                      defaultValue=""
                      disabled={dispatching === v.id}
                      style={{
                        padding: '6px 10px', borderRadius: 6, border: '1.5px solid #3b82f6',
                        color: '#3b82f6', fontSize: 13, cursor: 'pointer', background: '#eff6ff',
                      }}
                    >
                      <option value="">Dispatch to...</option>
                      {inspectors.map(i => (
                        <option key={i.id} value={i.id}>
                          {i.badge_number} — {i.username}
                        </option>
                      ))}
                    </select>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {violations.length === 0 && (
          <div style={{ padding: 40, textAlign: 'center', color: '#94a3b8' }}>No violations found.</div>
        )}
      </div>
    </div>
  );
}
