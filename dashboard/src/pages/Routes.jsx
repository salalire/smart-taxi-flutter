import { useEffect, useState } from 'react';
import { getRoutes, createRoute, updateRoute, deleteRoute, getZones } from '../api';
import PageHeader from '../components/PageHeader';

const empty = { name: '', zone: '', destination_zone: '', official_fare: '', max_deviation_km: 0.3, is_active: true };

export default function Routes() {
  const [routes, setRoutes] = useState([]);
  const [zones, setZones]   = useState([]);
  const [form, setForm]     = useState(null); // null = closed, {} = new, {id} = edit
  const [loading, setLoading] = useState(true);
  const [saving, setSaving]   = useState(false);
  const [error, setError]     = useState('');

  const load = async () => {
    const [r, z] = await Promise.all([getRoutes(), getZones()]);
    setRoutes(r.data);
    setZones(z.data);
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const openNew  = () => { setError(''); setForm({ ...empty }); };
  const openEdit = (r) => { setError(''); setForm({ ...r, zone: r.zone, destination_zone: r.destination_zone_id || '' }); };
  const closeForm = () => setForm(null);

  const save = async () => {
    setError('');
    setSaving(true);
    try {
      const payload = {
        name:             form.name,
        zone:             parseInt(form.zone),
        destination_zone: form.destination_zone ? parseInt(form.destination_zone) : null,
        official_fare:    parseFloat(form.official_fare),
        max_deviation_km: parseFloat(form.max_deviation_km),
        is_active:        form.is_active,
      };
      if (form.id) {
        await updateRoute(form.id, payload);
      } else {
        await createRoute(payload);
      }
      closeForm();
      await load();
    } catch (e) {
      setError(JSON.stringify(e.response?.data || e.message));
    } finally {
      setSaving(false);
    }
  };

  const remove = async (id) => {
    if (!window.confirm('Delete this route?')) return;
    await deleteRoute(id);
    load();
  };

  if (loading) return <div style={{ padding: 32, color: '#64748b' }}>Loading...</div>;

  return (
    <div style={{ padding: 32 }}>
      <PageHeader
        title="Routes"
        subtitle={`${routes.length} routes — ministry manages all route definitions`}
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
          <div style={{ background: '#fff', borderRadius: 16, padding: 32, width: 480, maxHeight: '90vh', overflowY: 'auto' }}>
            <h2 style={{ margin: '0 0 24px', fontSize: 18, color: '#1e293b' }}>
              {form.id ? 'Edit Route' : 'New Route'}
            </h2>

            {[
              { label: 'Route Name', key: 'name', type: 'text', placeholder: 'e.g. Megenagna → Bole' },
              { label: 'Official Fare (ETB)', key: 'official_fare', type: 'number', placeholder: '25' },
              { label: 'Max Deviation (km)', key: 'max_deviation_km', type: 'number', placeholder: '0.3' },
            ].map(({ label, key, type, placeholder }) => (
              <div key={key} style={{ marginBottom: 16 }}>
                <label style={{ display: 'block', fontSize: 13, fontWeight: 600, color: '#374151', marginBottom: 6 }}>{label}</label>
                <input
                  type={type} value={form[key] || ''} placeholder={placeholder}
                  onChange={(e) => setForm({ ...form, [key]: e.target.value })}
                  style={{ width: '100%', padding: '10px 12px', border: '1.5px solid #e2e8f0', borderRadius: 8, fontSize: 14, boxSizing: 'border-box' }}
                />
              </div>
            ))}

            {[
              { label: 'Origin Zone', key: 'zone' },
              { label: 'Destination Zone', key: 'destination_zone' },
            ].map(({ label, key }) => (
              <div key={key} style={{ marginBottom: 16 }}>
                <label style={{ display: 'block', fontSize: 13, fontWeight: 600, color: '#374151', marginBottom: 6 }}>{label}</label>
                <select
                  value={form[key] || ''}
                  onChange={(e) => setForm({ ...form, [key]: e.target.value })}
                  style={{ width: '100%', padding: '10px 12px', border: '1.5px solid #e2e8f0', borderRadius: 8, fontSize: 14, boxSizing: 'border-box' }}
                >
                  <option value="">Select zone{key === 'destination_zone' ? ' (optional)' : ''}</option>
                  {zones.map(z => <option key={z.id} value={z.id}>{z.name}</option>)}
                </select>
              </div>
            ))}

            <div style={{ marginBottom: 24, display: 'flex', alignItems: 'center', gap: 8 }}>
              <input type="checkbox" id="is_active" checked={form.is_active}
                onChange={(e) => setForm({ ...form, is_active: e.target.checked })} />
              <label htmlFor="is_active" style={{ fontSize: 14, color: '#374151' }}>Active route</label>
            </div>

            {error && <div style={{ background: '#fef2f2', border: '1px solid #fecaca', borderRadius: 8, padding: '10px 14px', marginBottom: 16, color: '#dc2626', fontSize: 13 }}>{error}</div>}

            <div style={{ display: 'flex', gap: 12 }}>
              <button onClick={closeForm} style={{ flex: 1, padding: '10px', border: '1.5px solid #e2e8f0', borderRadius: 8, cursor: 'pointer', fontSize: 14 }}>Cancel</button>
              <button onClick={save} disabled={saving} style={{ flex: 2, padding: '10px', background: '#16a34a', color: '#fff', border: 'none', borderRadius: 8, cursor: 'pointer', fontSize: 14, fontWeight: 600 }}>
                {saving ? 'Saving...' : 'Save Route'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Routes table */}
      <div style={{ background: '#fff', borderRadius: 12, boxShadow: '0 1px 3px rgba(0,0,0,0.08)', overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ background: '#f8fafc', borderBottom: '2px solid #e2e8f0' }}>
              {['Name', 'Origin Zone', 'Destination Zone', 'Fare', 'Max Deviation', 'Status', 'Actions'].map(h => (
                <th key={h} style={{ padding: '12px 16px', textAlign: 'left', fontSize: 13, fontWeight: 600, color: '#64748b' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {routes.map((r) => (
              <tr key={r.id} style={{ borderBottom: '1px solid #f1f5f9' }}>
                <td style={{ padding: '12px 16px', fontWeight: 600, color: '#1e293b' }}>{r.name}</td>
                <td style={{ padding: '12px 16px', fontSize: 13, color: '#64748b' }}>{r.zone_name || '—'}</td>
                <td style={{ padding: '12px 16px', fontSize: 13, color: '#64748b' }}>{r.destination_zone_name || '—'}</td>
                <td style={{ padding: '12px 16px', fontSize: 13 }}>ETB {r.official_fare}</td>
                <td style={{ padding: '12px 16px', fontSize: 13 }}>{r.max_deviation_km} km</td>
                <td style={{ padding: '12px 16px' }}>
                  <span style={{
                    padding: '3px 10px', borderRadius: 20, fontSize: 12, fontWeight: 600,
                    background: r.is_active ? '#f0fdf4' : '#f8fafc',
                    color: r.is_active ? '#16a34a' : '#94a3b8',
                  }}>{r.is_active ? 'Active' : 'Inactive'}</span>
                </td>
                <td style={{ padding: '12px 16px', display: 'flex', gap: 8 }}>
                  <button onClick={() => openEdit(r)} style={{ padding: '5px 12px', background: '#eff6ff', color: '#3b82f6', border: '1px solid #bfdbfe', borderRadius: 6, fontSize: 12, cursor: 'pointer' }}>Edit</button>
                  <button onClick={() => remove(r.id)} style={{ padding: '5px 12px', background: '#fef2f2', color: '#dc2626', border: '1px solid #fecaca', borderRadius: 6, fontSize: 12, cursor: 'pointer' }}>Delete</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {routes.length === 0 && <div style={{ padding: 40, textAlign: 'center', color: '#94a3b8' }}>No routes yet. Create one above.</div>}
      </div>
    </div>
  );
}
