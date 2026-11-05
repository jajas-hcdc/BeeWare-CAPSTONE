import React, { useState, useEffect } from 'react';
import { collection, onSnapshot } from 'firebase/firestore';
import { db } from '../firebase';
import { useAuth } from '../context/AuthContext';
import { ChevronRight, Wifi, Radio, Shield, RefreshCw, Menu } from 'lucide-react';

export default function Header({ 
  title, 
  section = 'Console', 
  onRefresh, 
  isRefreshing = false,
  onToggleMobileMenu 
}) {
  const { userRole, isOwner } = useAuth();
  const [timeStr, setTimeStr] = useState('');
  const [nodePill, setNodePill] = useState('BW-013230');

  useEffect(() => {
    const unsub = onSnapshot(collection(db, 'hives'), (snap) => {
      if (!snap.empty) {
        if (snap.size > 1) {
          setNodePill(`${snap.size} Nodes`);
        } else {
          const first = snap.docs[0].data();
          setNodePill(first.deviceId || 'BW-013230');
        }
      } else {
        setNodePill('No Nodes');
      }
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    const updateTime = () => {
      const now = new Date();
      setTimeStr(now.toLocaleTimeString('en-US', { 
        hour: '2-digit', 
        minute: '2-digit', 
        second: '2-digit', 
        timeZone: 'Asia/Manila' 
      }));
    };
    updateTime();
    const timer = setInterval(updateTime, 1000);
    return () => clearInterval(timer);
  }, []);

  return (
    <header className="h-14 bg-white border-b border-slate-200 px-3 sm:px-6 flex items-center justify-between sticky top-0 z-20 print:hidden min-w-0">
      {/* Left: Mobile Drawer Hamburger & Title / Breadcrumbs */}
      <div className="flex items-center gap-2 text-xs min-w-0 pr-2">
        <button
          type="button"
          onClick={onToggleMobileMenu}
          className="lg:hidden p-1.5 -ml-1 text-slate-600 hover:text-slate-900 hover:bg-slate-100 rounded-lg transition shrink-0 cursor-pointer"
          title="Toggle Navigation Menu"
          aria-label="Toggle navigation menu"
        >
          <Menu className="w-5 h-5" />
        </button>

        <span className="text-slate-400 font-medium hidden md:inline shrink-0">{section}</span>
        <ChevronRight className="w-3.5 h-3.5 text-slate-300 hidden md:inline shrink-0" />
        <h1 className="font-semibold text-slate-900 text-xs sm:text-sm tracking-tight truncate">
          {title}
        </h1>
      </div>

      {/* Right: Telemetry Status Bar */}
      <div className="flex items-center gap-1.5 sm:gap-3 shrink-0">
        {/* Live Firebase Sync Indicator */}
        <div className="flex items-center gap-1.5 text-xs text-slate-600 bg-slate-50 border border-slate-200/80 px-2 sm:px-2.5 py-1 rounded-md">
          <Wifi className="w-3.5 h-3.5 text-emerald-500 animate-pulse shrink-0" />
          <span className="text-[11px] font-medium text-slate-700 hidden sm:inline">Live Gateway</span>
          <span className="text-slate-300 hidden sm:inline">·</span>
          <span className="text-[10px] sm:text-[11px] font-mono text-slate-500 font-tabular">{timeStr || 'GMT+8'}</span>
        </div>

        {/* Node Status Pill */}
        <div className="hidden md:flex items-center gap-1.5 text-xs text-slate-600 bg-slate-50 border border-slate-200/80 px-2.5 py-1 rounded-md">
          <Radio className="w-3 h-3 text-slate-400 shrink-0" />
          <span className="text-[11px] font-mono text-slate-700">{nodePill}</span>
        </div>

        {/* Role Pill */}
        <span className={`text-[10px] font-mono uppercase tracking-wider px-1.5 sm:px-2 py-0.5 rounded font-bold border flex items-center gap-1 ${
          isOwner 
            ? 'bg-amber-50 text-amber-900 border-amber-300' 
            : 'bg-slate-100 text-slate-700 border-slate-300'
        }`}>
          <Shield className="w-2.5 h-2.5 shrink-0" />
          <span>{userRole || 'BEEKEEPER'}</span>
        </span>

        {/* Refresh Action */}
        {onRefresh && (
          <button
            type="button"
            onClick={onRefresh}
            disabled={isRefreshing}
            className="flex items-center gap-1 px-2 sm:px-2.5 py-1 text-xs font-medium text-slate-600 hover:text-slate-900 bg-white hover:bg-slate-50 rounded-md border border-slate-200 transition cursor-pointer"
            title="Refresh Telemetry"
          >
            <RefreshCw className={`w-3.5 h-3.5 text-slate-500 shrink-0 ${isRefreshing ? 'animate-spin' : ''}`} />
            <span className="hidden sm:inline">{isRefreshing ? 'Refreshing...' : 'Refresh'}</span>
          </button>
        )}
      </div>
    </header>
  );
}
