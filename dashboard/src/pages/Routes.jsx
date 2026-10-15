import { useEffect, useState } from 'react';
import { getRoutes, createRoute, updateRoute, deleteRoute, getZones, createZone } from '../api';
import PageHeader from '../components/PageHeader';

const emptyRoute = {
  name: '', zone: '', destination_zone: '',
  official_fare: '', max_deviation_km: 0.3, is_active: true,
};

const emptyZone = { name: '', center_latitude: '', center_longitude: '', radius_km: 2.0 };

// ── Inline zone creator shown inside the route form ───────────────────────────
function ZonePicker({ label, fieldKey, value, zones, onChange, onZoneCreated }) {
  const [creating, setCreating] = useState(false);
  const [zform, setZform]       = useState({ ...emptyZone });
  const [zsaving, setZsaving]   = useState(false);
  const [zerror, setZerror]     = useState('');

  const saveZone = async () => {
    setZerror('');
    if (!zform.name.trim()) { setZerror('Zone name is required.'); return; }
    setZsaving(true);
    try {
      const res = await createZone({
        name:              zform.name.trim(),
        center_latitude:   parseFloat(zform.center_latitude) || 9.03,
        center_longitude:  parseFloat(zform.center_longitude) || 38.74,
        radius_km:         parseFloat(zform.radius_km) || 2.0,
      });
      const newZone = res.data;
      await onZoneCreated(newZone); // reload zones list
      onChange(String(newZone.id));  // auto-select the new zone
      setCreating(false);
      setZform({ ...emptyZone });
    } catch (e) {
      setZerror(JSON.stringify(e.response?.data || e.message));
    } finally {
      setZsaving(false);
    }
  };

  return (
    <div style={{ marginBottom: 16 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
        <label style={{ fontSize: 13, fontWeight: 600, color: '#374151' }}>{label}</label>
        {!creating && (
          <button
            type="button"
            onClick={() => setCreating(true)}
            style={{
              fontSize: 12, color: '#16a34a', background: 'none',
              border: 'none', cursor: 'pointer', fontWeight: 600, padding: 0,
            }}
          >
            + Create new zone
          </button>
        )}
      </div>

      {creating ? (
        <div style={{
          border: '1.5px solid #bbf7d0', borderRadius: 10, padding: 14,
          background: '#f0fdf4', marginBottom: 4,
        }}>
          <div style={{ fontSize: 13, fontWeight: 600, color: '#16a34a', marginBottom: 10 }}>
            New Zone
          </div>
          {[
            { label: 'Zone Name *',         key: 'name',              placeholder: 'e.g. Megenagna' },
            { label: 'Center Latitude',      key: 'center_latitude',   placeholder: '9.0300' },
            { label: 'Center Longitude',     key: 'center_longitude',  placeholder: '38.7400' },
            { label: 'Radius (km)',          key: 'radius_km',         placeholder: '2.0' },
          ].map(({ label: fl, key, placeholder }) => (
            <div key={key} style={{ marginBottom: 8 }}>
              <label style={{ display: 'block', fontSize: 12, color: '#374151', marginBottom: 3 }}>{fl}</label>
              <input
                value={zform[key]}
                placeholder={placeholder}
                onChange={(e) => setZform({ ...zform, [key]: e.target.value })}
                style={{
                  width: '100%', padding: '7px 10px', border: '1.5px solid #d1fae5',
                  borderRadius: 6, fontSize: 13, boxSizing: 'border-box', background: '#fff',
                }}
              />
            </div>
          ))}
          {zerror && (
            <div style={{ color: '#dc2626', fontSize: 12, marginBottom: 8 }}>{zerror}</div>
          )}
          <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
            <button
              type="button"
              onClick={() => { setCreating(false); setZform({ ...emptyZone }); setZerror(''); }}
              style={{
                flex: 1, padding: '7px', border: '1.5px solid #e2e8f0',
                borderRadius: 6, cursor: 'pointer', fontSize: 13, background: '#fff',
              }}
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={saveZone}
              disabled={zsaving}
              style={{
                flex: 2, padding: '7px', background: '#16a34a', color: '#fff',
                border: 'none', borderRadius: 6, cursor: 'pointer',
                fontSize: 13, fontWeight: 600, opacity: zsaving ? 0.7 : 1,
              }}
            >
              {zsaving ? 'Creating...' : 'Create Zone'}
            </button>
          </div>
        </div>
      ) : (
        <select
          value={value}
          onChange={(e) => onChange(e.target.value)}
          style={{
            width: '100%', padding: '10px 12px', border: '1.5px solid #e2e8f0',
            borderRadius: 8, fontSize: 14, boxSizing: 'border-box', background: '#fff',
          }}
        >
          <option value="">
            Select zone{fieldKey === 'destination_zone' ? ' (optional)' : ''}
          </option>
          {zones.map(z => (
            <option key={z.id} value={z.id}>{z.name}</option>
          ))}
        </select>
      )}
    </div>
  );
}

// ── Main Routes page ──────────────────────────────────────────────────────────
export default function RoutesPage() {
  const [routes, setRoutes]   = useState([]);
  const [zones, setZones]     = useState([]);
  const [form, setForm]       = useState(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving]   = useState(false);
  const [error, setError]     = useState('');

  const loadRoutes = async () => {
    const [r, z] = await Promise.all([getRoutes(), getZones()]);
    setRoutes(r.data);
    setZones(z.data);
    setLoading(false);
  };

  // Called when a new zone is created inline — reload zones and return new zone
  const handleZoneCreated = async (newZone) => {
    const z = await getZones();
    setZones(z.data);
    return newZone;
  };

  useEffect(() => { loadRoutes(); }, []);

  const openNew  = () => { setError(''); setForm({ ...emptyRoute }); };
  const openEdit = (r) => {
    setError('');
    setForm({ ...r, zone: String(r.zone || ''), destination_zone: String(r.destination_zone_id || '') });
  };
  const closeForm = () => setForm(null);

  const save = async () => {
    setError('');
    if (!form.name.trim())   { setError('Route name is required.'); return; }
    if (!form.zone)          { setError('Origin zone is required.'); return; }
    if (!form.official_fare) { setError('Fare is required.'); return; }
    setSaving(true);
    try {
      const payload = {
        name:             form.name.trim(),
        zone:             parseInt(form.zone),
        destination_zone: form.destination_zone ? parseInt(form.destination_zone) : null,
        official_fare:    parseFloat(form.official_fare),
        max_deviation_km: parseFloat(form.max_deviation_km) || 0.3,
        is_active:        form.is_active,
      };
      if (form.id) {
        await updateRoute(form.id, payload);
      } else {
        await createRoute(payload);
      }
      closeForm();
      await loadRoutes();
    } catch (e) {
      setError(JSON.stringify(e.response?.data || e.message));
    } finally {
      setSaving(false);
    }
  };

  const remove = async (id) => {
    if (!window.confirm('Delete this route? This cannot be undone.')) return;
    await deleteRoute(id);
    loadRoutes();
  };

  if (loading) return <div style={{ padding: 32, color: '#64748b' }}>Loading...</div>;

  return (
    <div style={{ padding: 32 }}>
      <PageHeader
        title="Routes"
        subtitle={`${routes.length} route${routes.length !== 1 ? 's' : ''} — ministry manages all route definitions`}
        action={
          <button onClick={openNew} style={{
            padding: '10px 20px', background: '#16a34a', color: '#fff',
            border: 'none', borderRadius: 8, fontSize: 14, fontWeight: 600, cursor: 'pointer',
          }}>+ New Route</button>
        }
      />

      {/* Route form modal */}
      {form && (
        <div style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000,
        }}>
          <div style={{
            background: '#fff', borderRadius: 16, padding: 32,
            width: 500, maxHeight: '90vh', overflowY: 'auto',
            boxShadow: '0 20px 60px rgba(0,0,0,0.3)',
          }}>
            <h2 style={{ margin: '0 0 24px', fontSize: 18, color: '#1e293b' }}>
              {form.id ? 'Edit Route' : 'New Route'}
            </h2>

            {/* Text fields */}
            {[
              { label: 'Route Name *',        key: 'name',             type: 'text',   placeholder: 'e.g. Megenagna → Bole' },
              { label: 'Official Fare (ETB) *', key: 'official_fare',  type: 'number', placeholder: '25' },
              { label: 'Max Deviation (km)',   key: 'max_deviation_km', type: 'number', placeholder: '0.3' },
            ].map(({ label, key, type, placeholder }) => (
              <div key={key} style={{ marginBottom: 16 }}>
                <label style={{ display: 'block', fontSize: 13, fontWeight: 600, color: '#374151', marginBottom: 6 }}>
                  {label}
                </label>
                <input
                  type={type} value={form[key] ?? ''} placeholder={placeholder}
                  onChange={(e) => setForm({ ...form, [key]: e.target.value })}
                  style={{
                    width: '100%', padding: '10px 12px', border: '1.5px solid #e2e8f0',
                    borderRadius: 8, fontSize: 14, boxSizing: 'border-box', outline: 'none',
                  }}
                />
              </div>
            ))}

            {/* Zone pickers with inline creation */}
            <ZonePicker
              label="Origin Zone *"
              fieldKey="zone"
              value={form.zone}
              zones={zones}
              onChange={(v) => setForm({ ...form, zone: v })}
              onZoneCreated={handleZoneCreated}
            />
            <ZonePicker
              label="Destination Zone"
              fieldKey="destination_zone"
              value={form.destination_zone}
              zones={zones}
              onChange={(v) => setForm({ ...form, destination_zone: v })}
              onZoneCreated={handleZoneCreated}
            />

            {/* Active toggle */}
            <div style={{ marginBottom: 24, display: 'flex', alignItems: 'center', gap: 8 }}>
              <input
                type="checkbox" id="is_active" checked={form.is_active}
                onChange={(e) => setForm({ ...form, is_active: e.target.checked })}
              />
              <label htmlFor="is_active" style={{ fontSize: 14, color: '#374151', cursor: 'pointer' }}>
                Active route
              </label>
            </div>

            {error && (
              <div style={{
                background: '#fef2f2', border: '1px solid #fecaca', borderRadius: 8,
                padding: '10px 14px', marginBottom: 16, color: '#dc2626', fontSize: 13,
              }}>
                {error}
              </div>
            )}

            <div style={{ display: 'flex', gap: 12 }}>
              <button
                onClick={closeForm}
                style={{
                  flex: 1, padding: '10px', border: '1.5px solid #e2e8f0',
                  borderRadius: 8, cursor: 'pointer', fontSize: 14, background: '#fff',
                }}
              >
                Cancel
              </button>
              <button
                onClick={save}
                disabled={saving}
                style={{
                  flex: 2, padding: '10px', background: '#16a34a', color: '#fff',
                  border: 'none', borderRadius: 8, cursor: 'pointer',
                  fontSize: 14, fontWeight: 600, opacity: saving ? 0.7 : 1,
                }}
              >
                {saving ? 'Saving...' : 'Save Route'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Routes table */}
      <div style={{
        background: '#fff', borderRadius: 12,
        boxShadow: '0 1px 3px rgba(0,0,0,0.08)', overflow: 'hidden',
      }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ background: '#f8fafc', borderBottom: '2px solid #e2e8f0' }}>
              {['Name', 'Origin Zone', 'Destination Zone', 'Fare', 'Max Deviation', 'Status', 'Actions'].map(h => (
                <th key={h} style={{
                  padding: '12px 16px', textAlign: 'left',
                  fontSize: 13, fontWeight: 600, color: '#64748b',
                }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {routes.map((r) => (
              <tr key={r.id} style={{ borderBottom: '1px solid #f1f5f9' }}>
                <td style={{ padding: '12px 16px', fontWeight: 600, color: '#1e293b' }}>{r.name}</td>
                <td style={{ padding: '12px 16px', fontSize: 13, color: '#475569' }}>
                  {r.zone_name
                    ? <span style={{ background: '#f0fdf4', color: '#16a34a', padding: '2px 8px', borderRadius: 20, fontSize: 12, fontWeight: 600 }}>{r.zone_name}</span>
                    : <span style={{ color: '#cbd5e1' }}>—</span>}
                </td>
                <td style={{ padding: '12px 16px', fontSize: 13, color: '#475569' }}>
                  {r.destination_zone_name
                    ? <span style={{ background: '#eff6ff', color: '#3b82f6', padding: '2px 8px', borderRadius: 20, fontSize: 12, fontWeight: 600 }}>{r.destination_zone_name}</span>
                    : <span style={{ color: '#cbd5e1' }}>—</span>}
                </td>
                <td style={{ padding: '12px 16px', fontSize: 13, fontWeight: 600 }}>ETB {r.official_fare}</td>
                <td style={{ padding: '12px 16px', fontSize: 13, color: '#64748b' }}>{r.max_deviation_km} km</td>
                <td style={{ padding: '12px 16px' }}>
                  <span style={{
                    padding: '3px 10px', borderRadius: 20, fontSize: 12, fontWeight: 600,
                    background: r.is_active ? '#f0fdf4' : '#f8fafc',
                    color: r.is_active ? '#16a34a' : '#94a3b8',
                  }}>
                    {r.is_active ? 'Active' : 'Inactive'}
                  </span>
                </td>
                <td style={{ padding: '12px 16px' }}>
                  <div style={{ display: 'flex', gap: 8 }}>
                    <button
                      onClick={() => openEdit(r)}
                      style={{
                        padding: '5px 12px', background: '#eff6ff', color: '#3b82f6',
                        border: '1px solid #bfdbfe', borderRadius: 6, fontSize: 12, cursor: 'pointer',
                      }}
                    >
                      Edit
                    </button>
                    <button
                      onClick={() => remove(r.id)}
                      style={{
                        padding: '5px 12px', background: '#fef2f2', color: '#dc2626',
                        border: '1px solid #fecaca', borderRadius: 6, fontSize: 12, cursor: 'pointer',
                      }}
                    >
                      Delete
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {routes.length === 0 && (
          <div style={{ padding: 60, textAlign: 'center', color: '#94a3b8' }}>
            No routes yet. Click <strong>+ New Route</strong> to create one.
          </div>
        )}
      </div>
    </div>
  );
}
