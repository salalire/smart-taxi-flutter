import { useEffect, useState } from 'react';
import { getRelocations, decideRelocation } from '../api';
import PageHeader from '../components/PageHeader';

export default function Relocations() {
  const [relocations, setRelocations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [rejectReason, setRejectReason] = useState({});
  const [acting, setActing] = useState(null);

  const load = async () => {
    const res = await getRelocations();
    setRelocations(res.data);
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const handle = async (id, action) => {
    setActing(id);
    try {
      await decideRelocation(id, action, 4, rejectReason[id] || '');
      await load();
    } catch (e) {
      alert('Error: ' + (e.response?.data?.error || e.message));
    } finally {
      setActing(null);
    }
  };

  if (loading) return <div style={{ padding: 32, color: '#64748b' }}>Loading...</div>;

  return (
    <div style={{ padding: 32 }}>
      <PageHeader title="Relocations" subtitle={`${relocations.length} pending requests`} />

      {relocations.length === 0 ? (
        <div style={{ background: '#fff', borderRadius: 12, padding: 60, textAlign: 'center', color: '#94a3b8', boxShadow: '0 1px 3px rgba(0,0,0,0.08)' }}>
          ✅ No pending relocation requests.
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          {relocations.map((r) => (
            <div key={r.id} style={{
              background: '#fff', borderRadius: 12, padding: 24,
              boxShadow: '0 1px 3px rgba(0,0,0,0.08)',
              borderLeft: `4px solid ${r.initiated_by === 'system' ? '#3b82f6' : '#f97316'}`,
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 12 }}>
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <span style={{ fontWeight: 700, fontSize: 16, color: '#1e293b' }}>{r.driver_plate}</span>
                    <span style={{
                      padding: '2px 8px', borderRadius: 20, fontSize: 11, fontWeight: 600,
                      background: r.initiated_by === 'system' ? '#eff6ff' : '#fff7ed',
                      color: r.initiated_by === 'system' ? '#3b82f6' : '#f97316',
                    }}>
                      {r.initiated_by === 'system' ? '🤖 System' : '👤 Driver'}
                    </span>
                  </div>
                  <div style={{ fontSize: 14, color: '#64748b', marginTop: 6 }}>
                    {r.from_zone_name} → {r.to_zone_name}
                  </div>
                  <div style={{ fontSize: 13, color: '#94a3b8', marginTop: 4 }}>{r.reason}</div>
                </div>

                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, minWidth: 260 }}>
                  <input
                    placeholder="Rejection reason (optional)"
                    value={rejectReason[r.id] || ''}
                    onChange={(e) => setRejectReason({ ...rejectReason, [r.id]: e.target.value })}
                    style={{
                      padding: '8px 12px', border: '1.5px solid #e2e8f0', borderRadius: 6,
                      fontSize: 13, outline: 'none',
                    }}
                  />
                  <div style={{ display: 'flex', gap: 8 }}>
                    <button
                      onClick={() => handle(r.id, 'reject')}
                      disabled={acting === r.id}
                      style={{
                        flex: 1, padding: '8px', background: '#fef2f2', color: '#dc2626',
                        border: '1.5px solid #fecaca', borderRadius: 6,
                        fontSize: 13, fontWeight: 600, cursor: 'pointer',
                      }}
                    >
                      ✕ Reject
                    </button>
                    <button
                      onClick={() => handle(r.id, 'approve')}
                      disabled={acting === r.id}
                      style={{
                        flex: 1, padding: '8px', background: '#16a34a', color: '#fff',
                        border: 'none', borderRadius: 6,
                        fontSize: 13, fontWeight: 600, cursor: 'pointer',
                      }}
                    >
                      ✓ Approve
                    </button>
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
