import React, { useState, useEffect } from 'react';
import { collection, onSnapshot } from 'firebase/firestore';
import { db } from './firebase';
import { useAuth } from './context/AuthContext';
import Sidebar from './components/Sidebar';
import Header from './components/Header';
import DashboardView from './views/DashboardView';
import UsersView from './views/UsersView';
import HivesView from './views/HivesView';
import AudioVaultView from './views/AudioVaultView';
import AlertsView from './views/AlertsView';
import ExportView from './views/ExportView';
import LoginView from './views/LoginView';
import ScreenLoader from './components/ScreenLoader';

// Helper to check whether an alert item is currently active (not resolved)
function isItemActive(data) {
  if (!data) return false;
  if (data.resolved === true || data.resolved === 'true') return false;
  if (data.isResolved === true || data.isResolved === 'true') return false;
  const status = (data.status || '').toString().trim().toLowerCase();
  if (status === 'resolved' || status === 'archived' || status === 'dismissed') return false;
  return true;
}

export default function App() {
  const { 
    currentUser, 
    isOwner, 
    isAdmin, 
    userRole, 
    loading, 
    authLoading, 
    authLoadingMessage 
  } = useAuth();
  const [activeTab, setActiveTab] = useState('dashboard');
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [activeAlertCount, setActiveAlertCount] = useState(() => {
    try {
      const stored = localStorage.getItem('beeware_alerts_store_v1');
      if (stored) {
        const list = JSON.parse(stored);
        return list.filter(isItemActive).length;
      }
    } catch (e) {}
    return 0;
  });

  // Security guard: redirect Beekeeper accounts away from Admin-only tabs
  useEffect(() => {
    if (!isAdmin && (activeTab === 'users' || activeTab === 'export')) {
      setActiveTab('dashboard');
    }
  }, [isAdmin, activeTab]);

  useEffect(() => {
    const refreshFromLocalStorage = () => {
      try {
        const stored = localStorage.getItem('beeware_alerts_store_v1');
        if (stored) {
          const list = JSON.parse(stored);
          setActiveAlertCount(list.filter(isItemActive).length);
        } else {
          setActiveAlertCount(0);
        }
      } catch (e) {
        setActiveAlertCount(0);
      }
    };

    if (!currentUser) {
      setActiveAlertCount(0);
      return;
    }

    refreshFromLocalStorage();

    const unsub = onSnapshot(
      collection(db, 'alerts'), 
      (snap) => {
        if (!snap.empty) {
          const active = snap.docs.filter(d => isItemActive(d.data()));
          setActiveAlertCount(active.length);
        } else {
          refreshFromLocalStorage();
        }
      },
      (error) => {
        console.warn("Firestore alerts subscription notice:", error);
        refreshFromLocalStorage();
      }
    );

    window.addEventListener('beeware_alerts_updated', refreshFromLocalStorage);
    window.addEventListener('storage', refreshFromLocalStorage);

    return () => {
      unsub();
      window.removeEventListener('beeware_alerts_updated', refreshFromLocalStorage);
      window.removeEventListener('storage', refreshFromLocalStorage);
    };
  }, [currentUser]);

  if (loading) {
    return <ScreenLoader message="Initializing BeeWare Apiary Console..." />;
  }

  if (!currentUser) {
    return (
      <>
        {authLoading && (
          <ScreenLoader message={authLoadingMessage || 'Authenticating credentials...'} />
        )}
        <LoginView />
      </>
    );
  }

  const handleRefresh = () => {
    setIsRefreshing(true);
    setTimeout(() => {
      setIsRefreshing(false);
    }, 800);
  };

  const getHeaderInfo = () => {
    switch (activeTab) {
      case 'users':
        return { title: 'User & Role Management', subtitle: 'Role-Based Access Control: Owner vs. Beekeeper' };
      case 'hives':
        return { title: 'Hives & Nodes', subtitle: 'Physical box registry and ESP32 hardware bindings' };
      case 'audio':
        return { title: 'Acoustic Intelligence Vault', subtitle: 'Live 3.0s hive buzz WAV recordings & AI predictions' };
      case 'alerts':
        return { title: 'Alerts & Incidents', subtitle: 'Centralized apiary anomaly surveillance log' };
      case 'export':
        return { title: 'Data Export & Audit', subtitle: 'Research telemetry spreadsheets and printable summaries' };
      default:
        return { title: 'Apiary Executive Dashboard', subtitle: 'Real-time telemetry, colony condition, and health metrics' };
    }
  };

  const { title, subtitle } = getHeaderInfo();

  return (
    <div className="flex min-h-screen bg-slate-50 font-['Inter',sans-serif]">
      {/* Full-screen Loader Overlay during Logout / Auth transitions */}
      {authLoading && (
        <ScreenLoader message={authLoadingMessage || 'Signing out of Apiary Console...'} />
      )}

      {/* Sidebar Navigation (Desktop Persistent + Mobile/Tablet Slide-over) */}
      <Sidebar 
        activeTab={activeTab} 
        setActiveTab={setActiveTab} 
        alertCount={activeAlertCount} 
        mobileOpen={mobileMenuOpen}
        onCloseMobile={() => setMobileMenuOpen(false)}
      />

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col min-w-0 overflow-y-auto h-screen">
        <Header 
          title={title} 
          subtitle={subtitle} 
          onRefresh={handleRefresh}
          isRefreshing={isRefreshing}
          onToggleMobileMenu={() => setMobileMenuOpen(prev => !prev)}
        />

        {/* Role Permissions Notice Banner */}
        {!isOwner && (
          <div className="bg-slate-100/90 border-b border-slate-200 px-4 sm:px-8 py-2 text-xs font-medium text-slate-800 flex items-center justify-between print:hidden">
            {userRole === 'admin' ? (
              <span className="text-indigo-950 font-medium">
                Signed in as <strong>Admin ({currentUser.email})</strong>. Full operational permissions enabled (hives registry, user directory, telemetry exports, alert incidents). User role promotions are restricted to Owners.
              </span>
            ) : (
              <span className="text-slate-800 font-medium">
                Signed in as <strong>Beekeeper ({currentUser.email})</strong>. Real-time telemetry & hive surveillance active. User directory, telemetry exports, and hives modifications are restricted to Admins and Owners.
              </span>
            )}
          </div>
        )}

        <main className="flex-1 pb-12">
          {activeTab === 'dashboard' && <DashboardView onNavigate={(tab) => setActiveTab(tab)} />}
          {activeTab === 'users' && (isAdmin ? <UsersView /> : <DashboardView onNavigate={(tab) => setActiveTab(tab)} />)}
          {activeTab === 'hives' && <HivesView />}
          {activeTab === 'audio' && <AudioVaultView />}
          {activeTab === 'alerts' && <AlertsView />}
          {activeTab === 'export' && (isAdmin ? <ExportView /> : <DashboardView onNavigate={(tab) => setActiveTab(tab)} />)}
        </main>
      </div>
    </div>
  );
}
