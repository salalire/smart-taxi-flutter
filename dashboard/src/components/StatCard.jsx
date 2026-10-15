export default function StatCard({ title, value, sub, color = '#4ade80', icon }) {
  return (
    <div style={{
      background: '#fff', borderRadius: 12, padding: '20px 24px',
      boxShadow: '0 1px 3px rgba(0,0,0,0.08)', borderTop: `4px solid ${color}`,
      minWidth: 150,
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div>
          <div style={{ fontSize: 13, color: '#64748b', fontWeight: 500 }}>{title}</div>
          <div style={{ fontSize: 32, fontWeight: 700, color: '#1e293b', marginTop: 4 }}>{value ?? '—'}</div>
          {sub && <div style={{ fontSize: 12, color: '#94a3b8', marginTop: 4 }}>{sub}</div>}
        </div>
        {icon && <div style={{ fontSize: 28, opacity: 0.6 }}>{icon}</div>}
      </div>
    </div>
  );
}
