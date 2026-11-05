import React, { useState, useEffect, useMemo } from 'react';
import { 
  collection, 
  onSnapshot, 
  doc, 
  setDoc, 
  deleteDoc, 
  serverTimestamp 
} from 'firebase/firestore';
import { db } from '../firebase';
import { useAuth } from '../context/AuthContext';
import { 
  AlertCircle, 
  AlertTriangle, 
  Info, 
  CheckCircle2, 
  RotateCcw, 
  Trash2, 
  Bell, 
  Clock 
} from 'lucide-react';

const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000; // 7 days in milliseconds

/**
 * Checks whether an incident is older than 7 days based on resolvedAt or timestamp
 */
function isOlderThan7Days(item) {
  const time = item.resolvedAt || item.epoch || (item.timestamp?.toDate ? item.timestamp.toDate().getTime() : Date.parse(item.timestamp));
  if (!time || isNaN(time)) return false;
  return (Date.now() - time) > SEVEN_DAYS_MS;
}

/**
 * Formats remaining days before 7-day automatic purge
 */
function getRemainingRetention(item) {
  const time = item.resolvedAt || item.epoch || (item.timestamp?.toDate ? item.timestamp.toDate().getTime() : Date.parse(item.timestamp));
  if (!time || isNaN(time)) return '7 days';
  const elapsed = Date.now() - time;
  const remainingMs = SEVEN_DAYS_MS - elapsed;
  if (remainingMs <= 0) return 'Expiring';
  const days = Math.ceil(remainingMs / (24 * 60 * 60 * 1000));
  if (days <= 1) {
    const hours = Math.max(1, Math.ceil(remainingMs / (60 * 60 * 1000)));
    return `${hours} hour${hours > 1 ? 's' : ''}`;
  }
  return `${days} days`;
}

export default function AlertsView() {
  const { currentUser, isAdmin } = useAuth();
  const [activeTab, setActiveTab] = useState('active'); // 'active' | 'history' (Admin/Owner only)
  const [alerts, setAlerts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [severityFilter, setSeverityFilter] = useState('ALL');
  const [actionNotice, setActionNotice] = useState(null);
  const [pendingDeleteAlert, setPendingDeleteAlert] = useState(null);

  // Fallback to active tab if user is a beekeeper
  useEffect(() => {
    if (!isAdmin && activeTab === 'history') {
      setActiveTab('active');
    }
  }, [isAdmin, activeTab]);

  // 1. Subscribe to Firestore /alerts collection
  useEffect(() => {
    const unsub = onSnapshot(collection(db, 'alerts'), async (snap) => {
      let list = [];
      const expiredDocIds = [];

      snap.docs.forEach((d) => {
        const data = d.data();
        const item = {
          id: d.id,
          ...data,
          epoch: data.epoch || (data.timestamp?.toDate ? data.timestamp.toDate().getTime() : Date.now()),
          timestampFormatted: data.timestampFormatted || (data.timestamp?.toDate 
            ? data.timestamp.toDate().toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) 
            : 'Recent')
        };

        // 7-day expiration check
        if (isOlderThan7Days(item)) {
          expiredDocIds.push(d.id);
        } else {
          list.push(item);
        }
      });

      // Automatically purge documents older than 7 days from Firestore
      if (expiredDocIds.length > 0) {
        expiredDocIds.forEach(async (expiredId) => {
          try {
            await deleteDoc(doc(db, 'alerts', expiredId));
          } catch (e) {
            console.error("Auto-purge error:", e);
          }
        });
      }

      // If Firestore is completely fresh/empty, check local cache or seed only once on first install
      if (list.length === 0 && snap.empty) {
        const storedLocal = localStorage.getItem('beeware_alerts_store_v1');
        if (storedLocal !== null) {
          try {
            const parsed = JSON.parse(storedLocal);
            list = Array.isArray(parsed) ? parsed.filter(item => !isOlderThan7Days(item)) : [];
          } catch (e) {
            console.error(e);
          }
        } else {
          // Brand new first-time initial seed
          const seededFlag = localStorage.getItem('beeware_alerts_seeded_v1');
          if (!seededFlag) {
            localStorage.setItem('beeware_alerts_seeded_v1', 'true');
            const nowMs = Date.now();
            const seedAlerts = [
              {
                id: 'alert_queenless_roar',
                title: 'Queenless Roar Distress (365 Hz)',
                message: 'Acoustic frequency spiked above 300 Hz threshold. Missing Queen Mandibular Pheromone response.',
                severity: 'Critical',
                hiveId: 'Hive 1 (BW-013230)',
                recommendation: 'Perform brood frame inspection for emergency queen cells.',
                timestampFormatted: 'Oct 28, 09:30 AM',
                epoch: nowMs - (24 * 60 * 60 * 1000), // 1 day ago
                status: 'active',
                resolved: false,
                isResolved: false
              },
              {
                id: 'alert_high_humidity',
                title: 'High Humidity Warning (85.1%)',
                message: 'Internal relative humidity reached 85.1% (≥ 85% safety boundary). Risk of dampness.',
                severity: 'Warning',
                hiveId: 'Hive 1 (BW-013230)',
                recommendation: 'Check upper ventilation screen and inner moisture covers.',
                timestampFormatted: 'Oct 28, 11:15 AM',
                epoch: nowMs - (18 * 60 * 60 * 1000), // 18 hours ago
                status: 'active',
                resolved: false,
                isResolved: false
              }
            ];

            list = seedAlerts;
            seedAlerts.forEach(async (s) => {
              try {
                await setDoc(doc(db, 'alerts', s.id), s);
              } catch (err) {
                console.warn("Could not seed to Firestore:", err);
              }
            });
          }
        }
      }

      setAlerts(list);
      setLoading(false);
      localStorage.setItem('beeware_alerts_store_v1', JSON.stringify(list));
      window.dispatchEvent(new Event('beeware_alerts_updated'));
    }, (error) => {
      console.warn("Firestore alerts subscription error:", error);
      const storedLocal = localStorage.getItem('beeware_alerts_store_v1');
      if (storedLocal) {
        try {
          setAlerts(JSON.parse(storedLocal));
        } catch (e) {}
      }
      setLoading(false);
    });

    return () => unsub();
  }, [currentUser]);

  // Show temporary action feedback banner
  const triggerNotice = (msg) => {
    setActionNotice(msg);
    setTimeout(() => {
      setActionNotice(null);
    }, 4000);
  };

  // Resolve an active incident
  const handleResolveAlert = async (alertItem) => {
    const resolvedTimestamp = Date.now();
    const resolvedTimeFormatted = new Date(resolvedTimestamp).toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
    const resolver = currentUser?.displayName || currentUser?.email?.split('@')[0] || 'Admin';

    const updatedItem = {
      ...alertItem,
      status: 'resolved',
      resolved: true,
      isResolved: true,
      resolvedAt: resolvedTimestamp,
      resolvedTimeFormatted: resolvedTimeFormatted,
      resolvedBy: resolver,
      updatedAt: serverTimestamp()
    };

    try {
      // 1. Update Firestore
      await setDoc(doc(db, 'alerts', alertItem.id), updatedItem, { merge: true });
    } catch (err) {
      console.warn("Firestore update error (persisting locally):", err);
    }

    // 2. Update local state
    setAlerts(prev => {
      const next = prev.map(a => a.id === alertItem.id ? updatedItem : a);
      localStorage.setItem('beeware_alerts_store_v1', JSON.stringify(next));
      window.dispatchEvent(new Event('beeware_alerts_updated'));
      return next;
    });

    triggerNotice(`Incident "${alertItem.title}" marked as resolved and moved to 7-Day History.`);
  };

  // Re-open an incident back to active
  const handleReopenAlert = async (alertItem) => {
    const reopenedItem = {
      ...alertItem,
      status: 'active',
      resolved: false,
      isResolved: false,
      reopenedAt: Date.now(),
      updatedAt: serverTimestamp()
    };
    delete reopenedItem.resolvedAt;
    delete reopenedItem.resolvedTimeFormatted;

    try {
      await setDoc(doc(db, 'alerts', alertItem.id), reopenedItem, { merge: true });
    } catch (err) {
      console.warn("Firestore reopen error:", err);
    }

    setAlerts(prev => {
      const next = prev.map(a => a.id === alertItem.id ? reopenedItem : a);
      localStorage.setItem('beeware_alerts_store_v1', JSON.stringify(next));
      window.dispatchEvent(new Event('beeware_alerts_updated'));
      return next;
    });

    triggerNotice(`Incident "${alertItem.title}" re-opened and returned to Active Surveillance.`);
  };

  // Permanently delete a single incident from history
  const confirmDeleteAlert = async () => {
    if (!isAdmin || !pendingDeleteAlert) return;
    const id = pendingDeleteAlert.id;
    try {
      await deleteDoc(doc(db, 'alerts', id));
    } catch (err) {
      console.warn("Delete error:", err);
    }

    setAlerts(prev => {
      const next = prev.filter(a => a.id !== id);
      localStorage.setItem('beeware_alerts_store_v1', JSON.stringify(next));
      window.dispatchEvent(new Event('beeware_alerts_updated'));
      return next;
    });

    setPendingDeleteAlert(null);
    triggerNotice("Incident record deleted.");
  };

  // Manually purge all resolved incidents older than 7 days
  const handlePurgeExpired = async () => {
    if (!isAdmin) return;
    const expired = alerts.filter(isOlderThan7Days);
    if (expired.length === 0) {
      triggerNotice("All records are currently within the 7-day retention period. No expired records found.");
      return;
    }

    for (const exp of expired) {
      try {
        await deleteDoc(doc(db, 'alerts', exp.id));
      } catch (err) {
        console.warn("Purge error:", err);
      }
    }

    setAlerts(prev => {
      const next = prev.filter(a => !isOlderThan7Days(a));
      localStorage.setItem('beeware_alerts_store_v1', JSON.stringify(next));
      window.dispatchEvent(new Event('beeware_alerts_updated'));
      return next;
    });

    triggerNotice(`Purged ${expired.length} expired incident(s) older than 7 days.`);
  };

  // Split into Active vs Resolved History (supports boolean resolved, isResolved, and status)
  const isAlertActive = (a) => {
    if (!a) return false;
    if (a.resolved === true || a.resolved === 'true') return false;
    if (a.isResolved === true || a.isResolved === 'true') return false;
    const status = (a.status || '').toString().trim().toLowerCase();
    if (status === 'resolved' || status === 'archived' || status === 'dismissed') return false;
    return true;
  };

  const activeAlerts = useMemo(() => {
    return alerts.filter(isAlertActive);
  }, [alerts]);

  const historyAlerts = useMemo(() => {
    return alerts
      .filter(a => !isAlertActive(a) && !isOlderThan7Days(a))
      .sort((a, b) => (b.resolvedAt || 0) - (a.resolvedAt || 0));
  }, [alerts]);

  // Apply severity filter
  const displayedActive = useMemo(() => {
    if (severityFilter === 'ALL') return activeAlerts;
    return activeAlerts.filter(a => (a.severity || 'info').toLowerCase() === severityFilter.toLowerCase());
  }, [activeAlerts, severityFilter]);

  const displayedHistory = useMemo(() => {
    if (severityFilter === 'ALL') return historyAlerts;
    return historyAlerts.filter(a => (a.severity || 'info').toLowerCase() === severityFilter.toLowerCase());
  }, [historyAlerts, severityFilter]);

  const getSeverityBadge = (severity) => {
    const s = (severity || 'info').toLowerCase();
    if (s === 'critical') {
      return (
        <span className="flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-mono font-medium bg-red-50 text-red-800 border border-red-200">
          <AlertCircle className="w-3.5 h-3.5 text-red-600" />
          <span>CRITICAL</span>
        </span>
      );
    }
    if (s === 'warning') {
      return (
        <span className="flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-mono font-medium bg-amber-50 text-amber-800 border border-amber-200">
          <AlertTriangle className="w-3.5 h-3.5 text-amber-600" />
          <span>WARNING</span>
        </span>
      );
    }
    return (
      <span className="flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-mono font-medium bg-slate-100 text-slate-700 border border-slate-200">
        <Info className="w-3.5 h-3.5 text-blue-600" />
        <span>INFO</span>
      </span>
    );
  };

  return (
    <div className="p-3 sm:p-5 md:p-6 max-w-7xl mx-auto space-y-5 sm:space-y-6 min-w-0">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-4 border-b border-slate-200/80 gap-3">
        <div>
          <h2 className="text-lg font-bold text-slate-900 tracking-tight">Alert & Incident Surveillance</h2>
          <p className="text-xs text-slate-500">Real-time incident log for queen distress, climate shifts, and sensor dropouts</p>
        </div>

        {/* Severity Filter controls */}
        <div className="flex items-center gap-1.5 self-start sm:self-auto">
          {['ALL', 'CRITICAL', 'WARNING', 'INFO'].map((sev) => (
            <button
              key={sev}
              onClick={() => setSeverityFilter(sev)}
              className={`px-2.5 py-1 rounded-md text-xs font-medium transition ${
                severityFilter === sev
                  ? 'bg-slate-900 text-white shadow-2xs font-semibold'
                  : 'bg-white text-slate-600 border border-slate-200 hover:bg-slate-50'
              }`}
            >
              {sev}
            </button>
          ))}
        </div>
      </div>

      {/* Action Notification Banner */}
      {actionNotice && (
        <div className="bg-emerald-50 border border-emerald-200 rounded-lg p-3 text-xs text-emerald-800 flex items-center justify-between shadow-2xs animate-in fade-in duration-150">
          <span>{actionNotice}</span>
          <button onClick={() => setActionNotice(null)} className="text-emerald-700 hover:text-emerald-900 font-bold ml-2">
            ✕
          </button>
        </div>
      )}

      {/* Main Tabs: Active Incidents vs 7-Day History */}
      <div className="flex items-center justify-between border-b border-slate-200 pb-0">
        <div className="flex space-x-6">
          <button
            onClick={() => setActiveTab('active')}
            className={`py-2 px-1 border-b-2 text-xs font-semibold tracking-wide transition flex items-center gap-2 ${
              activeTab === 'active'
                ? 'border-amber-500 text-amber-700'
                : 'border-transparent text-slate-500 hover:text-slate-800'
            }`}
          >
            <Bell className="w-3.5 h-3.5" />
            <span>Active Incidents</span>
            <span className={`text-[10px] px-1.5 py-0.2 rounded-full font-bold ${
              activeAlerts.length > 0 
                ? 'bg-red-500 text-white' 
                : 'bg-slate-100 text-slate-500'
            }`}>
              {activeAlerts.length}
            </span>
          </button>

          {isAdmin && (
            <button
              onClick={() => setActiveTab('history')}
              className={`py-2 px-1 border-b-2 text-xs font-semibold tracking-wide transition flex items-center gap-2 ${
                activeTab === 'history'
                  ? 'border-amber-500 text-amber-700'
                  : 'border-transparent text-slate-500 hover:text-slate-800'
              }`}
            >
              <Clock className="w-3.5 h-3.5" />
              <span>Incident History (7-Day Log)</span>
              <span className="text-[10px] px-1.5 py-0.2 rounded-full font-bold bg-slate-100 text-slate-600">
                {historyAlerts.length}
              </span>
            </button>
          )}
        </div>

        {/* 7-Day Policy indicator */}
        {isAdmin && (
          <div className="hidden sm:flex items-center gap-1.5 text-[11px] text-slate-500 font-mono">
            <Clock className="w-3 h-3 text-slate-400" />
            <span>7-Day Retention Auto-Purge</span>
          </div>
        )}
      </div>

      {/* 7-Day Auto-Purge Policy Information Banner */}
      {isAdmin && (
        <div className="bg-slate-50 border border-slate-200/80 rounded-xl p-3 flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-xs text-slate-600">
          <div>
            <span>
              <strong>7-Day Retention Policy:</strong> Resolved incidents stay archived in the history log for up to <strong>7 days</strong>, after which they are automatically cleared to keep surveillance responsive.
            </span>
          </div>
          <button
            onClick={handlePurgeExpired}
            className="flex items-center gap-1 px-2.5 py-1 text-[11px] font-medium text-slate-700 hover:text-slate-900 bg-white hover:bg-slate-100 border border-slate-200 rounded-md transition self-start sm:self-auto shrink-0 shadow-2xs"
          >
            <Trash2 className="w-3 h-3 text-slate-500" />
            <span>Purge Expired</span>
          </button>
        </div>
      )}

      {/* TAB 1: ACTIVE INCIDENTS */}
      {activeTab === 'active' && (
        <div className="space-y-3">
          {displayedActive.length === 0 ? (
            <div className="bg-white p-12 rounded-xl border border-slate-200 text-center space-y-2">
              <h3 className="text-sm font-bold text-slate-800">No Active Incidents</h3>
              <p className="text-xs text-slate-400">All apiary sensor telemetry, acoustic frequencies, and hive conditions are operating nominally.</p>
            </div>
          ) : (
            displayedActive.map((alert) => (
              <div 
                key={alert.id}
                className="bg-white rounded-xl border border-slate-200/90 p-4 shadow-2xs hover:border-slate-300 transition space-y-3"
              >
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                  <div className="flex items-center gap-2.5">
                    {getSeverityBadge(alert.severity)}
                    <h3 className="font-semibold text-slate-900 text-xs">{alert.title}</h3>
                  </div>
                  <div className="flex items-center gap-2 text-xs text-slate-400 font-mono">
                    <span>{alert.hiveId || 'Hive 1'}</span>
                    <span>·</span>
                    <span>{alert.timestampFormatted}</span>
                  </div>
                </div>

                <p className="text-xs text-slate-600 leading-relaxed">
                  {alert.message}
                </p>

                {alert.recommendation && (
                  <div className="p-2.5 bg-slate-50 rounded-lg border border-slate-100 text-xs text-slate-700">
                    <span className="font-semibold text-slate-900 mr-1.5">Action:</span>
                    <span>{alert.recommendation}</span>
                  </div>
                )}

                <div className="pt-2 border-t border-slate-100 flex items-center justify-end">
                  <button
                    onClick={() => handleResolveAlert(alert)}
                    className="flex items-center gap-1.5 px-3.5 py-1.5 bg-slate-900 hover:bg-slate-800 text-white rounded-md text-xs font-medium transition shadow-2xs"
                  >
                    <CheckCircle2 className="w-3.5 h-3.5" />
                    <span>Resolve Incident</span>
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {/* TAB 2: INCIDENT HISTORY (7-DAY LOG - ADMIN/OWNER ONLY) */}
      {activeTab === 'history' && isAdmin && (
        <div className="space-y-3">
          {displayedHistory.length === 0 ? (
            <div className="bg-white p-12 rounded-xl border border-slate-200 text-center space-y-2">
              <h3 className="text-sm font-bold text-slate-800">Incident History is Clean</h3>
              <p className="text-xs text-slate-400">Resolved incidents from the past 7 days will appear here before being automatically cleared.</p>
            </div>
          ) : (
            displayedHistory.map((alert) => (
              <div 
                key={alert.id}
                className="bg-white rounded-xl border border-slate-200/90 p-4 shadow-2xs space-y-3 opacity-90 hover:opacity-100 transition"
              >
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                  <div className="flex items-center gap-2.5">
                    {getSeverityBadge(alert.severity)}
                    <span className="flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-mono font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                      <CheckCircle2 className="w-3 h-3" />
                      <span>RESOLVED</span>
                    </span>
                    <h3 className="font-semibold text-slate-800 text-xs line-through decoration-slate-400">
                      {alert.title}
                    </h3>
                  </div>

                  <div className="flex items-center gap-2 text-[11px] text-slate-400 font-mono">
                    <span>{alert.hiveId || 'Hive 1'}</span>
                    <span>·</span>
                    <span className="text-amber-700 bg-amber-50 px-1.5 py-0.2 rounded border border-amber-200">
                      Expires in {getRemainingRetention(alert)}
                    </span>
                  </div>
                </div>

                <p className="text-xs text-slate-500 leading-relaxed">
                  {alert.message}
                </p>

                {alert.recommendation && (
                  <div className="p-2.5 bg-slate-50/80 rounded-lg border border-slate-100 text-xs text-slate-600">
                    <span className="font-medium text-slate-800 mr-1.5">Remedy Action:</span>
                    <span>{alert.recommendation}</span>
                  </div>
                )}

                {/* Resolution Audit Metadata */}
                <div className="pt-2 border-t border-slate-100 flex flex-col sm:flex-row sm:items-center justify-between text-[11px] text-slate-500 gap-2">
                  <div className="font-mono">
                    <span>Reported: {alert.timestampFormatted}</span>
                    <span className="mx-2">•</span>
                    <span className="text-emerald-700 font-semibold">
                      Resolved: {alert.resolvedTimeFormatted || 'Recently'} by {alert.resolvedBy || 'Admin'}
                    </span>
                  </div>

                  <div className="flex items-center gap-2 self-end sm:self-auto">
                    <button
                      type="button"
                      onClick={() => handleReopenAlert(alert)}
                      className="flex items-center gap-1 px-2.5 py-1 text-slate-600 hover:text-slate-900 bg-white hover:bg-slate-50 border border-slate-200 rounded-md transition shadow-2xs text-[11px] font-medium"
                      title="Re-open incident back to active list"
                    >
                      <RotateCcw className="w-3 h-3" />
                      <span>Re-open</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => setPendingDeleteAlert(alert)}
                      className="flex items-center gap-1 px-2 py-1 text-red-500 hover:text-red-700 hover:bg-red-50 rounded transition text-[11px] font-medium"
                      title="Delete record from history"
                    >
                      <Trash2 className="w-3 h-3" />
                      <span>Delete</span>
                    </button>
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {/* Customized Confirmation Modal for Deleting Incident Record */}
      {pendingDeleteAlert && (
        <div className="fixed inset-0 z-50 bg-slate-900/50 backdrop-blur-xs flex items-center justify-center p-4 animate-in fade-in duration-150">
          <div className="bg-white rounded-2xl max-w-sm w-full p-6 shadow-2xl border border-slate-200 text-center space-y-4 animate-in zoom-in-95 duration-150">
            <div className="w-10 h-10 mx-auto rounded-full bg-red-50 text-red-600 flex items-center justify-center">
              <AlertTriangle className="w-5 h-5" />
            </div>
            <div className="space-y-1">
              <h3 className="text-base font-bold text-slate-900">Delete Incident Record?</h3>
              <p className="text-xs text-slate-500">
                Are you sure you want to permanently remove this incident from history?
              </p>
            </div>

            <div className="p-3 bg-slate-50 rounded-xl border border-slate-200/80 text-xs text-slate-800 font-medium text-left space-y-1">
              <div className="font-bold text-slate-900">{pendingDeleteAlert.title}</div>
              <div className="text-[11px] text-slate-500">{pendingDeleteAlert.hiveId || 'Hive 1'} • {pendingDeleteAlert.timestampFormatted}</div>
            </div>

            <div className="flex items-center justify-center gap-2.5 pt-2">
              <button
                type="button"
                onClick={() => setPendingDeleteAlert(null)}
                className="flex-1 px-4 py-2 text-slate-700 hover:bg-slate-100 rounded-lg text-xs font-semibold transition border border-slate-200"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={confirmDeleteAlert}
                className="flex-1 px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg text-xs font-semibold transition shadow-sm"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
