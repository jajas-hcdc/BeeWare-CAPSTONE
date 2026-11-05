import React from 'react';
import { useAuth } from '../context/AuthContext';
import { 
  LayoutDashboard, 
  Layers, 
  Volume2, 
  Radio, 
  Users, 
  Download, 
  Shield, 
  LogOut,
  X 
} from 'lucide-react';

export default function Sidebar({ 
  activeTab, 
  setActiveTab, 
  alertCount = 0, 
  mobileOpen = false, 
  onCloseMobile 
}) {
  const { currentUser, userProfile, userRole, isAdmin, logout } = useAuth();

  const mainNav = [
    { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
    { id: 'hives', label: 'Hives', icon: Layers },
    { id: 'audio', label: 'Acoustic Vault', icon: Volume2 },
    { id: 'alerts', label: 'Alert Incidents', icon: Radio, count: alertCount },
  ];

  const adminNav = [
    { id: 'users', label: 'User Directory', icon: Users, badge: 'RBAC' },
    { id: 'export', label: 'Telemetry Exports', icon: Download },
  ];

  const displayName = userProfile?.displayName || currentUser?.email?.split('@')[0] || 'User';
  const initial = displayName.charAt(0).toUpperCase();

  const handleNavClick = (id) => {
    setActiveTab(id);
    if (onCloseMobile) onCloseMobile();
  };

  const handleLogout = () => {
    if (onCloseMobile) onCloseMobile();
    logout();
  };

  const renderNavContent = (isMobile = false) => (
    <div className="flex flex-col h-full">
      {/* Brand & Workspace */}
      <div className="h-14 px-4 border-b border-slate-800 flex items-center justify-between shrink-0">
        <div className="leading-tight">
          <span className="font-bold text-sm tracking-tight text-white block">
            BeeWare
          </span>
          <span className="text-[11px] text-slate-400 font-medium block">
            Apiary Console
          </span>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-[10px] font-mono tracking-wider bg-slate-800 text-slate-300 border border-slate-700 px-1.5 py-0.5 rounded">
            v2.0
          </span>
          {isMobile && (
            <button
              type="button"
              onClick={onCloseMobile}
              className="p-1 rounded text-slate-400 hover:text-white hover:bg-slate-800 transition cursor-pointer"
              aria-label="Close navigation menu"
            >
              <X className="w-5 h-5" />
            </button>
          )}
        </div>
      </div>

      {/* Navigation Groups */}
      <nav className="flex-1 px-2.5 py-4 space-y-6 overflow-y-auto">
        {/* Core Monitoring */}
        <div>
          <span className="px-2.5 text-[10px] font-semibold tracking-wider text-slate-400 uppercase block mb-1.5">
            Surveillance
          </span>
          <div className="space-y-0.5">
            {mainNav.map((item) => {
              const Icon = item.icon;
              const isActive = activeTab === item.id;
              return (
                <button
                  key={item.id}
                  onClick={() => handleNavClick(item.id)}
                  className={`w-full flex items-center justify-between px-3 py-2.5 sm:py-2 rounded-md text-xs font-medium transition-colors cursor-pointer ${
                    isActive
                      ? 'bg-slate-800 text-amber-400 font-semibold shadow-xs'
                      : 'text-slate-300 hover:text-white hover:bg-slate-800/60'
                  }`}
                >
                  <div className="flex items-center gap-2.5">
                    <Icon className="w-4 h-4 shrink-0" />
                    <span>{item.label}</span>
                  </div>
                  {item.count > 0 && (
                    <span className="text-[10px] bg-red-500/20 text-red-400 border border-red-500/30 font-semibold px-1.5 py-0.2 rounded-full">
                      {item.count}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        </div>

        {/* Administration & Roles (Admin & Owner Only) */}
        {isAdmin && (
          <div>
            <span className="px-2.5 text-[10px] font-semibold tracking-wider text-slate-400 uppercase block mb-1.5">
              Administration
            </span>
            <div className="space-y-0.5">
              {adminNav.map((item) => {
                const Icon = item.icon;
                const isActive = activeTab === item.id;
                return (
                  <button
                    key={item.id}
                    onClick={() => handleNavClick(item.id)}
                    className={`w-full flex items-center justify-between px-3 py-2.5 sm:py-2 rounded-md text-xs font-medium transition-colors cursor-pointer ${
                      isActive
                        ? 'bg-slate-800 text-amber-400 font-semibold shadow-xs'
                        : 'text-slate-300 hover:text-white hover:bg-slate-800/60'
                    }`}
                  >
                    <div className="flex items-center gap-2.5">
                      <Icon className="w-4 h-4 shrink-0" />
                      <span>{item.label}</span>
                    </div>
                    {item.badge && (
                      <span className="text-[9px] font-mono uppercase bg-slate-800 text-slate-400 border border-slate-700 px-1 py-0.2 rounded">
                        {item.badge}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
          </div>
        )}
      </nav>

      {/* Footer Profile & Session */}
      <div className="p-3 border-t border-slate-800 bg-slate-950/60 shrink-0">
        <div className="flex items-center justify-between p-2.5 rounded-lg bg-slate-900 border border-slate-800 text-xs">
          <div className="flex items-center gap-2.5 min-w-0">
            <div className="w-7 h-7 rounded-md bg-slate-800 text-slate-200 border border-slate-700 flex items-center justify-center font-bold text-xs shrink-0">
              {initial}
            </div>
            <div className="min-w-0">
              <span className="font-semibold text-white block truncate leading-tight">
                {displayName}
              </span>
              <span className={`text-[10px] font-mono tracking-wide flex items-center gap-1 ${
                userRole === 'owner' 
                  ? 'text-amber-400 font-semibold' 
                  : userRole === 'admin' 
                  ? 'text-indigo-400 font-semibold' 
                  : 'text-slate-400'
              }`}>
                <Shield className="w-2.5 h-2.5 shrink-0" />
                <span className="truncate">{userRole?.toUpperCase() || 'BEEKEEPER'}</span>
              </span>
            </div>
          </div>
          <button
            onClick={handleLogout}
            title="Sign Out"
            className="p-1.5 text-slate-400 hover:text-white hover:bg-slate-800 rounded transition cursor-pointer shrink-0"
          >
            <LogOut className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  );

  return (
    <>
      {/* 1. Desktop Persistent Sidebar (hidden on phones & tablets) */}
      <aside className="hidden lg:flex w-60 bg-slate-900 text-slate-300 flex-col h-screen border-r border-slate-800 shrink-0 sticky top-0 select-none print:hidden">
        {renderNavContent(false)}
      </aside>

      {/* 2. Mobile & Tablet Slide-over Backdrop */}
      <div 
        className={`fixed inset-0 bg-slate-950/60 backdrop-blur-xs z-40 transition-opacity duration-300 lg:hidden ${
          mobileOpen ? 'opacity-100 pointer-events-auto' : 'opacity-0 pointer-events-none'
        }`}
        onClick={onCloseMobile}
        aria-hidden="true"
      />

      {/* 3. Mobile & Tablet Slide-over Drawer */}
      <aside 
        className={`fixed inset-y-0 left-0 w-72 max-w-[85vw] bg-slate-900 text-slate-300 z-50 flex flex-col shadow-2xl transition-transform duration-300 ease-in-out lg:hidden select-none ${
          mobileOpen ? 'translate-x-0' : '-translate-x-full'
        }`}
      >
        {renderNavContent(true)}
      </aside>
    </>
  );
}
