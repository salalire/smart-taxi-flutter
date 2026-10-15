import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './context/AuthContext';
import Layout      from './components/Layout';
import Login       from './pages/Login';
import Dashboard   from './pages/Dashboard';
import LiveMap     from './pages/LiveMap';
import Zones       from './pages/Zones';
import RoutesPage  from './pages/Routes';
import Drivers     from './pages/Drivers';
import Violations  from './pages/Violations';
import Relocations from './pages/Relocations';
import Reports     from './pages/Reports';

function ProtectedRoute({ children }) {
  const { user, loading } = useAuth();
  if (loading) return null;
  return user ? children : <Navigate to="/login" replace />;
}

function AppRoutes() {
  const { user, loading } = useAuth();
  if (loading) return null;

  return (
    <Routes>
      <Route path="/login" element={user ? <Navigate to="/" replace /> : <Login />} />
      <Route path="/" element={<ProtectedRoute><Layout /></ProtectedRoute>}>
        <Route index          element={<Dashboard />} />
        <Route path="map"     element={<LiveMap />} />
        <Route path="zones"   element={<Zones />} />
        <Route path="routes"  element={<RoutesPage />} />
        <Route path="drivers" element={<Drivers />} />
        <Route path="violations"  element={<Violations />} />
        <Route path="relocations" element={<Relocations />} />
        <Route path="reports"     element={<Reports />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <AppRoutes />
      </AuthProvider>
    </BrowserRouter>
  );
}
