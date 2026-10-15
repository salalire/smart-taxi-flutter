import { useEffect, useState } from 'react';
import { getPassengerReports, getDemandReports, getObservations, markReportReviewed, markObservationReviewed } from '../api';
import PageHeader from '../components/PageHeader';

const tabs = ['Passenger Reports', 'Demand Reports', 'Observations'];

export default function Reports() {
  const [tab, setTab]         = useState(0);
  const [reports, setReports] = useState([]);
  const [demand, setDemand]   = useState([]);
  const [obs, setObs]         = useState([]);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    const [r, d, o] = await Promise.all([getPassengerReports(), getDemandReports(), getObservations()]);
    setReports(r.data); setDemand(d.data); setObs(o.data);
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const reviewReport = async (id) => { await markReportReviewed(id); load(); };
  const reviewObs    = async (id) => { await markObservationReviewed(id); load(); };

  if (loading) return <div style={{ padding: 32, color: '#64748b' }}>Loading...</div>;

  return (
    <div style={{ padding: 32 }}>
      <PageHeader title="Reports" subtitle="Passenger reports, demand signals and field observations" />

      {/* Tab bar */}
      <div style={{ display: 'flex', gap: 4, background: '#f1f5f9', padding: 4, borderRadius: 10, marginBottom: 24, width: 'fit-content' }}>
        {tabs.map((t, i) => (
          <button key={t} onClick={() => setTab(i)} style={{
            padding: '8px 20px', borderRadius: 7, border: 'none', cursor: 'pointer',
            background: tab === i ? '#fff' : 'transparent',
            color: tab === i ? '#1e293b' : '#64748b',
            fontWeight: tab === i ? 600 : 400, fontSize: 14,
            boxShadow: tab === i ? '0 1px 3px rgba(0,0,0,0.1)' : 'none',
          }}>{t}</button>
        ))}
      </div>

      {/* Passenger reports */}
      {tab === 0 && (
        <div style={{ background: '#fff', borderRadius: 12, boxShadow: '0 1px 3px rgba(0,0,0,0.08)', overflow: 'hidden' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ background: '#f8fafc', borderBottom: '2px solid #e2e8f0' }}>
                {['Plate', 'Type', 'Reporter', 'Zone', 'Date', 'Status', 'Action'].map(h => (
                  <th key={h} style={{ padding: '12px 16px', textAlign: 'left', fontSize: 13, fontWeight: 600, color: '#64748b' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {reports.map((r) => (
                <tr key={r.id} style={{ borderBottom: '1px solid #f1f5f9', opacity: r.is_reviewed ? 0.6 : 1 }}>
                  <td style={{ padding: '12px 16px', fontWeight: 700, color: '#1e293b' }}>{r.plate_number}</td>
                  <td style={{ padding: '12px 16px', fontSize: 13 }}>{r.report_type?.replace(/_/g, ' ')}</td>
                  <td style={{ padding: '12px 16px', fontSize: 13, color: '#64748b' }}>{r.passenger_username}</td>
                  <td style={{ padding: '12px 16px', fontSize: 13, color: '#64748b' }}>{r.zone_name || '—'}</td>
                  <td style={{ padding: '12px 16px', fontSize: 13, color: '#64748b' }}>{r.created_at?.substring(0, 10)}</td>
                  <td style={{ padding: '12px 16px' }}>
                    {r.is_reviewed
                      ? <span style={{ color: '#16a34a', fontSize: 13, fontWeight: 600 }}>✓ Reviewed</span>
                      : <span style={{ color: '#f97316', fontSize: 13, fontWeight: 600 }}>Pending</span>}
                  </td>
                  <td style={{ padding: '12px 16px' }}>
                    {!r.is_reviewed && (
                      <button onClick={() => reviewReport(r.id)} style={{
                        padding: '5px 12px', background: '#16a34a', color: '#fff',
                        border: 'none', borderRadius: 6, fontSize: 12, cursor: 'pointer',
                      }}>Mark Reviewed</button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {reports.length === 0 && <div style={{ padding: 40, textAlign: 'center', color: '#94a3b8' }}>No reports.</div>}
        </div>
      )}

      {/* Demand reports */}
      {tab === 1 && (
        <div style={{ background: '#fff', borderRadius: 12, boxShadow: '0 1px 3px rgba(0,0,0,0.08)', overflow: 'hidden' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ background: '#f8fafc', borderBottom: '2px solid #e2e8f0' }}>
                {['Zone', 'Type', 'Reporter', 'Weight', 'Date'].map(h => (
                  <th key={h} style={{ padding: '12px 16px', textAlign: 'left', fontSize: 13, fontWeight: 600, color: '#64748b' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {demand.map((r) => (
                <tr key={r.id} style={{ borderBottom: '1px solid #f1f5f9' }}>
                  <td style={{ padding: '12px 16px', fontWeight: 700, color: '#1e293b' }}>{r.zone_name}</td>
                  <td style={{ padding: '12px 16px', fontSize: 13 }}>{r.report_type?.replace(/_/g, ' ')}</td>
                  <td style={{ padding: '12px 16px', fontSize: 13, color: '#64748b' }}>{r.reporter_username}</td>
                  <td style={{ padding: '12px 16px', fontSize: 13 }}>{r.weight}</td>
                  <td style={{ padding: '12px 16px', fontSize: 13, color: '#64748b' }}>{r.created_at?.substring(0, 10)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {demand.length === 0 && <div style={{ padding: 40, textAlign: 'center', color: '#94a3b8' }}>No demand reports.</div>}
        </div>
      )}

      {/* Observations */}
      {tab === 2 && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {obs.map((o) => (
            <div key={o.id} style={{
              background: '#fff', borderRadius: 12, padding: 20,
              boxShadow: '0 1px 3px rgba(0,0,0,0.08)',
              borderLeft: `4px solid ${o.is_reviewed ? '#94a3b8' : '#3b82f6'}`,
              opacity: o.is_reviewed ? 0.7 : 1,
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                <div>
                  <div style={{ fontWeight: 700, color: '#1e293b' }}>
                    {o.observation_type?.replace(/_/g, ' ')} — {o.zone_name}
                  </div>
                  <div style={{ fontSize: 13, color: '#64748b', marginTop: 4 }}>
                    Inspector: {o.inspector_badge}
                    {o.plate_number ? ` · Plate: ${o.plate_number}` : ''}
                  </div>
                  {o.description && <div style={{ fontSize: 13, color: '#475569', marginTop: 4 }}>{o.description}</div>}
                </div>
                {!o.is_reviewed && (
                  <button onClick={() => reviewObs(o.id)} style={{
                    padding: '6px 14px', background: '#3b82f6', color: '#fff',
                    border: 'none', borderRadius: 6, fontSize: 12, cursor: 'pointer', whiteSpace: 'nowrap',
                  }}>Mark Reviewed</button>
                )}
                {o.is_reviewed && <span style={{ color: '#16a34a', fontSize: 13, fontWeight: 600 }}>✓ Reviewed</span>}
              </div>
            </div>
          ))}
          {obs.length === 0 && <div style={{ background: '#fff', borderRadius: 12, padding: 60, textAlign: 'center', color: '#94a3b8' }}>No observations.</div>}
        </div>
      )}
    </div>
  );
}
