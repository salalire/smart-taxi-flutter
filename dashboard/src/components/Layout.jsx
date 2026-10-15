import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

const navItems = [
  { to: '/',             icon: '📊', label: 'Dashboard'   },
  { to: '/map',          icon: '🗺️',  label: 'Live Map'    },
  { to: '/zones',        icon: '📍', label: 'Zones'       },
  { to: '/routes',       icon: '🛣️',  label: 'Routes'      },
  { to: '/drivers',      icon: '🚐', label: 'Drivers'     },
  { to: '/violations',   icon: '⚠️',  label: 'Violations'  },
  { to: '/relocations',  icon: '🔄', label: 'Relocations' },
  { to: '/reports',      icon: '📋', label: 'Reports'     },
];

export default function Layout() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  return (
    <div style={{ display: 'flex', minHeight: '100vh', fontFamily: 'system-ui, sans-serif' }}>
      {/* Sidebar */}
      <nav style={{
        width: 220, background: '#1a1f2e', color: '#fff',
        display: 'flex', flexDirection: 'column', padding: '0',
        position: 'fixed', height: '100vh', overflowY: 'auto',
      }}>
        <div style={{ padding: '20px 16px', borderBottom: '1px solid #2d3348' }}>
          <div style={{ fontSize: 18, fontWeight: 700, color: '#4ade80' }}>🚌 Smart Taxi</div>
          <div style={{ fontSize: 12, color: '#94a3b8', marginTop: 4 }}>Ministry Dashboard</div>
        </div>

        <div style={{ flex: 1, padding: '8px 0' }}>
          {navItems.map(({ to, icon, label }) => (
            <NavLink
              key={to}
              to={to}
              end={to === '/'}
              style={({ isActive }) => ({
                display: 'flex', alignItems: 'center', gap: 10,
                padding: '10px 16px', textDecoration: 'none',
                color: isActive ? '#4ade80' : '#cbd5e1',
                background: isActive ? '#2d3348' : 'transparent',
                borderLeft: isActive ? '3px solid #4ade80' : '3px solid transparent',
                fontSize: 14, fontWeight: isActive ? 600 : 400,
                transition: 'all 0.15s',
              })}
            >
              <span>{icon}</span>
              <span>{label}</span>
            </NavLink>
          ))}
        </div>

        <div style={{ padding: '16px', borderTop: '1px solid #2d3348' }}>
          <div style={{ fontSize: 13, color: '#94a3b8', marginBottom: 8 }}>
            👤 {user?.username}
          </div>
          <button
            onClick={handleLogout}
            style={{
              width: '100%', padding: '8px', background: '#ef4444',
              color: '#fff', border: 'none', borderRadius: 6,
              cursor: 'pointer', fontSize: 13, fontWeight: 600,
            }}
          >
            Logout
          </button>
        </div>
      </nav>

      {/* Main content */}
      <main style={{
        marginLeft: 220,
        width: 'calc(100% - 220px)',
        background: '#f8fafc',
        minHeight: '100vh',
        boxSizing: 'border-box',
      }}>
        <Outlet />
      </main>
    </div>
  );
}
