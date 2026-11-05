import React, { useState, useEffect, useMemo } from 'react';
import { ref, onValue, query, limitToLast } from 'firebase/database';
import { collection, onSnapshot } from 'firebase/firestore';
import { rtdb, db } from '../firebase';
import { useAuth } from '../context/AuthContext';
import { getNodeWatchdogStatus } from '../utils/heartbeat';
import { getConditionInfo } from '../utils/condition';
import { 
  Activity, 
  Volume2, 
  Thermometer, 
  Droplets, 
  Users, 
  Layers, 
  Wifi, 
  Zap, 
  Radio, 
  CheckCircle2, 
  AlertTriangle,
  ArrowUpRight,
  MapPin,
  ChevronDown,
  ChevronUp,
  LayoutList,
  Cpu
} from 'lucide-react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer
} from 'recharts';

export default function DashboardView({ onNavigate }) {
  const { isAdmin } = useAuth();
  const [hives, setHives] = useState([]);
  const [users, setUsers] = useState([]);
  const [telemetryMap, setTelemetryMap] = useState({});
  // SessionStorage Caching initialization
  const [historyMap, setHistoryMap] = useState(() => {
    const initial = {};
    try {
      ['BW-013230', 'BW-08266C'].forEach(devId => {
        const cached = sessionStorage.getItem(`beeware_tel_hist_${devId}`);
        if (cached) {
          initial[devId] = JSON.parse(cached);
        }
      });
    } catch (e) {}
    return initial;
  });
  const [loading, setLoading] = useState(true);

  // Time-Range Filtering state (24 Hours | 7 Days | 30 Days matching mobile app)
  const [timeRange, setTimeRange] = useState('24h');

  // Grouping and Filtering state
  const [selectedYardFilter, setSelectedYardFilter] = useState('ALL');
  const [viewMode, setViewMode] = useState('grouped'); // 'grouped' | 'flat'
  const [collapsedYards, setCollapsedYards] = useState({});

  // 1. Fetch Firestore Hives & Users
  useEffect(() => {
    const unsubHives = onSnapshot(collection(db, 'hives'), (snap) => {
      const list = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      setHives(list);
    });

    const unsubUsers = onSnapshot(collection(db, 'users'), (snap) => {
      setUsers(snap.docs.map(d => ({ id: d.id, ...d.data() })));
    });

    return () => {
      unsubHives();
      unsubUsers();
    };
  }, []);

  // 2. Dynamically subscribe to RTDB Telemetry & History for all devices in fleet
  useEffect(() => {
    const deviceIds = hives.length > 0 
      ? Array.from(new Set(hives.map(h => (h.deviceId || 'BW-013230').trim())))
      : ['BW-013230'];

    const unsubscribers = [];

    deviceIds.forEach(devId => {
      // RTDB live telemetry
      const telRef = ref(rtdb, `telemetry/${devId}`);
      const unsubTel = onValue(telRef, (snapshot) => {
        if (snapshot.exists()) {
          setTelemetryMap(prev => ({ ...prev, [devId]: snapshot.val() }));
        }
      });
      unsubscribers.push(unsubTel);

      // RTDB telemetry history starting from Oct 13 matching mobile app
      const histQuery = ref(rtdb, `telemetry_history/${devId}`);
      const unsubHist = onValue(histQuery, (snapshot) => {
        if (snapshot.exists()) {
          const val = snapshot.val();
          const pts = [];
          Object.keys(val).forEach(key => {
            const item = val[key];
            if (item && item.temperature !== undefined) {
              let epoch = item.epoch || item.createdAt || item.created_at || 0;
              if (epoch > 0 && epoch < 1700000000000 && epoch >= 1700000000) {
                epoch *= 1000;
              }
              if (!epoch && item.timestamp) {
                const parsed = Date.parse(item.timestamp);
                if (!isNaN(parsed)) epoch = parsed;
              }
              pts.push({
                time: item.timestamp || item.recorded_time || key,
                epoch: epoch || Date.now(),
                temp: parseFloat(item.temperature) || 0,
                humidity: parseFloat(item.humidity) || 0,
                freq: parseInt(item.frequency || item.frequency_hz) || 0,
              });
            }
          });
          // Sort chronologically
          pts.sort((a, b) => (a.epoch || 0) - (b.epoch || 0));

          // Cache in sessionStorage for instant offline and view-switch retrieval
          try {
            sessionStorage.setItem(`beeware_tel_hist_${devId}`, JSON.stringify(pts));
          } catch (e) {}

          setHistoryMap(prev => ({ ...prev, [devId]: pts }));
        }
      });
      unsubscribers.push(unsubHist);
    });

    setLoading(false);

    return () => {
      unsubscribers.forEach(unsub => unsub());
    };
  }, [hives]);

  // Normalize location names
  const normalizeLocation = (loc) => {
    if (!loc || loc.trim() === '' || loc.trim().toLowerCase() === 'apiary box') {
      return 'Toril, Catigan APIARY';
    }
    return loc.trim();
  };

  // Display hives list (deduplicated by deviceId, empty if none registered)
  const displayDevices = useMemo(() => {
    const map = new Map();
    hives.forEach(h => {
      const key = (h.deviceId || h.id || '').trim().toUpperCase();
      if (!key) return;
      if (!map.has(key)) {
        map.set(key, h);
      } else {
        const existing = map.get(key);
        if ((!existing.name || existing.name.toUpperCase() === existing.deviceId?.toUpperCase()) && h.name && h.name.toUpperCase() !== h.deviceId?.toUpperCase()) {
          map.set(key, h);
        }
      }
    });
    return Array.from(map.values());
  }, [hives]);

  // Group devices by physical yard location
  const groupedDevices = useMemo(() => {
    const groups = {};
    displayDevices.forEach(hive => {
      const loc = normalizeLocation(hive.location);
      if (!groups[loc]) {
        groups[loc] = [];
      }
      groups[loc].push(hive);
    });
    return groups;
  }, [displayDevices]);

  const allYards = Object.keys(groupedDevices);

  // Filtered devices based on selected yard tab
  const filteredDevices = useMemo(() => {
    if (selectedYardFilter === 'ALL') {
      return displayDevices;
    }
    return displayDevices.filter(h => normalizeLocation(h.location) === selectedYardFilter);
  }, [displayDevices, selectedYardFilter]);

  // Visible yards to render in grouped mode
  const visibleYards = useMemo(() => {
    if (selectedYardFilter === 'ALL') {
      return allYards;
    }
    return allYards.filter(y => y === selectedYardFilter);
  }, [allYards, selectedYardFilter]);

  const toggleYardCollapse = (yardName) => {
    setCollapsedYards(prev => ({
      ...prev,
      [yardName]: !prev[yardName]
    }));
  };

  // Helper to get time series points filtered by selected range (24h | 7d | 30d) matching mobile app
  const getDeviceHistoryPoints = (devId, hive, liveTel, range = '24h') => {
    let rawPts = historyMap[devId];
    if (!rawPts || rawPts.length === 0) {
      try {
        const cached = sessionStorage.getItem(`beeware_tel_hist_${devId}`);
        if (cached) rawPts = JSON.parse(cached);
      } catch (e) {}
    }

    if (rawPts && rawPts.length > 0) {
      const validEpochs = rawPts.map(p => p.epoch).filter(Boolean);
      const maxEpoch = validEpochs.length > 0 ? Math.max(...validEpochs) : Date.now();
      
      let cutoffMs = 24 * 60 * 60 * 1000; // 24 Hours default
      if (range === '7d' || range === '7 Days') cutoffMs = 7 * 24 * 60 * 60 * 1000;
      else if (range === '30d' || range === '30 Days') cutoffMs = 30 * 24 * 60 * 60 * 1000;

      const filtered = rawPts.filter(p => (p.epoch || 0) >= (maxEpoch - cutoffMs));
      const count = (range === '24h' || range === '24 Hours') ? 12 : ((range === '7d' || range === '7 Days') ? 20 : 30);
      const sliced = filtered.length >= 3 ? filtered : rawPts.slice(-count);

      const shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      const isDayView = range === '24h' || range === '24 Hours';

      // Check if points span multiple calendar days
      const dayMap = new Map();
      sliced.forEach(p => {
        const dt = p.epoch ? new Date(p.epoch) : new Date();
        const dayKey = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
        if (!dayMap.has(dayKey)) dayMap.set(dayKey, []);
        dayMap.get(dayKey).push(p);
      });
      const isMultiDay = dayMap.size >= 2;

      return sliced.map(p => {
        const dt = p.epoch ? new Date(p.epoch) : null;
        let timeLabel = p.time || 'Recent';

        if (dt && !isNaN(dt.getTime())) {
          const mon = shortMonths[dt.getMonth()];
          const day = String(dt.getDate()).padStart(2, '0');
          let hr = dt.getHours();
          const ampm = hr >= 12 ? 'PM' : 'AM';
          hr = hr % 12 || 12;
          const min = String(dt.getMinutes()).padStart(2, '0');

          if (isDayView) {
            timeLabel = p.time || `${hr}:${min} ${ampm}`;
          } else if (isMultiDay) {
            timeLabel = `${mon} ${day}`;
          } else {
            timeLabel = `${mon} ${day} · ${hr}:${min} ${ampm}`;
          }
        }
        return {
          ...p,
          time: timeLabel
        };
      });
    }

    // Baseline fallback points if device has no historical logs in RTDB yet
    const baseTemp = parseFloat(liveTel?.temperature || hive?.temperature || 28.5);
    const baseHum = parseFloat(liveTel?.humidity || hive?.humidity || 84.0);
    const baseFreq = parseInt(liveTel?.frequency || hive?.acoustic || 110);

    const fullMock = [
      { time: '11:35 AM', epoch: Date.now() - 36000000, temp: Number((baseTemp - 0.4).toFixed(1)), humidity: Number((baseHum + 0.6).toFixed(1)), freq: Math.max(90, baseFreq - 6) },
      { time: '01:50 PM', epoch: Date.now() - 25000000, temp: Number((baseTemp - 0.1).toFixed(1)), humidity: Number((baseHum + 0.2).toFixed(1)), freq: baseFreq },
      { time: '04:12 PM', epoch: Date.now() - 14000000, temp: Number(baseTemp.toFixed(1)), humidity: Number(baseHum.toFixed(1)), freq: baseFreq + 8 },
      { time: '06:25 PM', epoch: Date.now() - 7000000, temp: Number((baseTemp + 0.3).toFixed(1)), humidity: Number((baseHum - 0.5).toFixed(1)), freq: Math.max(90, baseFreq - 3) },
      { time: '07:39 PM', epoch: Date.now() - 1000000, temp: Number(baseTemp.toFixed(1)), humidity: Number(baseHum.toFixed(1)), freq: baseFreq },
    ];

    if (range === '7d' || range === '30d') {
      const now = new Date();
      const shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      const mon = shortMonths[now.getMonth()];
      return fullMock.map((m, i) => {
        const day = Math.max(1, now.getDate() - (fullMock.length - 1 - i));
        return {
          ...m,
          time: `${mon} ${String(day).padStart(2, '0')}`
        };
      });
    }

    return fullMock.slice(-3);
  };

  // Calculate telemetry values and aggregates for the currently active filter scope
  const activeTelemetryList = filteredDevices.map((hive, idx) => {
    const devId = (hive.deviceId || `BW-NODE-${idx + 1}`).trim();
    const liveTel = telemetryMap[devId];

    // Temperature extraction
    let tNum = null;
    if (liveTel?.temperature !== undefined) {
      tNum = typeof liveTel.temperature === 'number' 
        ? liveTel.temperature 
        : parseFloat(liveTel.temperature.toString().replace(/[^0-9.]/g, ''));
    } else if (hive.temperature) {
      tNum = parseFloat(hive.temperature.toString().replace(/[^0-9.]/g, ''));
    }
    if (isNaN(tNum) || tNum === null) tNum = 29.2;

    // Humidity extraction
    let hNum = null;
    if (liveTel?.humidity !== undefined) {
      hNum = typeof liveTel.humidity === 'number' 
        ? liveTel.humidity 
        : parseFloat(liveTel.humidity.toString().replace(/[^0-9.]/g, ''));
    } else if (hive.humidity) {
      hNum = parseFloat(hive.humidity.toString().replace(/[^0-9.]/g, ''));
    }
    if (isNaN(hNum) || hNum === null) hNum = 84.5;

    // Frequency extraction
    let fNum = null;
    if (liveTel?.frequency !== undefined) {
      fNum = parseInt(liveTel.frequency);
    } else if (liveTel?.acoustic) {
      fNum = parseInt(liveTel.acoustic.toString().replace(/[^0-9]/g, ''));
    } else if (hive.acoustic) {
      fNum = parseInt(hive.acoustic.toString().replace(/[^0-9]/g, ''));
    }
    if (isNaN(fNum) || fNum === null) fNum = 102;

    // Health Score extraction
    let sNum = liveTel?.healthScore || hive.healthScore || 90;

    // Condition extraction
    const rawCond = liveTel?.conditionLabel || hive.conditionLabel || 'Queen Present';
    const condInfo = getConditionInfo(rawCond, fNum);

    return {
      hive,
      devId,
      name: hive.name || `Hive ${idx + 1}`,
      temp: tNum,
      humidity: hNum,
      frequency: fNum,
      healthScore: sNum,
      condition: condInfo.label,
      conditionInfo: condInfo
    };
  });

  const hasMultipleDevices = activeTelemetryList.length >= 2;

  // Averages / Aggregates for top cards
  const avgTemp = (activeTelemetryList.reduce((acc, d) => acc + d.temp, 0) / (activeTelemetryList.length || 1)).toFixed(1);
  const avgHum = (activeTelemetryList.reduce((acc, d) => acc + d.humidity, 0) / (activeTelemetryList.length || 1)).toFixed(1);
  const avgFreq = Math.round(activeTelemetryList.reduce((acc, d) => acc + d.frequency, 0) / (activeTelemetryList.length || 1));
  const avgHealthScore = Math.round(activeTelemetryList.reduce((acc, d) => acc + d.healthScore, 0) / (activeTelemetryList.length || 1));

  // Breakdown strings for display under each metric card
  const tempBreakdown = activeTelemetryList.map(d => `${d.name.split(' ')[0] || d.devId}: ${d.temp}°C`).join(' · ');
  const humBreakdown = activeTelemetryList.map(d => `${d.name.split(' ')[0] || d.devId}: ${d.humidity}%`).join(' · ');
  const freqBreakdown = activeTelemetryList.map(d => `${d.name.split(' ')[0] || d.devId}: ${d.frequency} Hz`).join(' · ');
  const nodesString = activeTelemetryList.map(d => d.devId).join(', ');

  const alertDevice = activeTelemetryList.find(d => d.conditionInfo?.isAlert);
  const isOverallAlert = Boolean(alertDevice);
  const overallCondition = alertDevice 
    ? (hasMultipleDevices ? `${alertDevice.condition} (${alertDevice.name || alertDevice.devId})` : alertDevice.condition)
    : (hasMultipleDevices ? `Queen Present (${activeTelemetryList.length} Nodes Nominal)` : 'Queen Present');

  const ownersCount = users.filter(u => u.role === 'owner').length;
  const beekeepersCount = users.filter(u => u.role === 'beekeeper').length;
  const totalUsersCount = users.length > 0 ? users.length : ((ownersCount + beekeepersCount) || 8);
  const totalHives = displayDevices.length;

  // Render individual hive card (Time series chart + hardware status)
  const renderDeviceCard = (hive, index) => {
    const devId = (hive.deviceId || `BW-NODE-${index + 1}`).trim();
    const liveTel = telemetryMap[devId];
    const pts = getDeviceHistoryPoints(devId, hive, liveTel, timeRange);
    
    const devTemp = liveTel?.temperature !== undefined 
      ? (typeof liveTel.temperature === 'number' ? `${liveTel.temperature}°C` : liveTel.temperature)
      : (hive.temperature || '29.2°C');
    const devHum = liveTel?.humidity !== undefined 
      ? (typeof liveTel.humidity === 'number' ? `${liveTel.humidity}%` : liveTel.humidity)
      : (hive.humidity || '84.5%');
    const devFreq = liveTel?.frequency !== undefined 
      ? `${liveTel.frequency} Hz` 
      : (liveTel?.acoustic || hive.acoustic || '102 Hz');
    const rawDevCondition = liveTel?.conditionLabel || hive.conditionLabel || 'Queen Present';
    const condInfo = getConditionInfo(rawDevCondition, devFreq);
    
    const watchdog = getNodeWatchdogStatus(liveTel || hive);
    const rssi = liveTel?.wifi_rssi || -65;
    const power = liveTel?.power_source || hive.batteryLevel || 'Plugged In';
    const lastSeen = liveTel?.timestamp || liveTel?.lastAudioRecordedTime || hive.updated || 'Just now';
    const locName = normalizeLocation(hive.location);

    return (
      <div key={hive.id || devId || index} className="space-y-3">
        {/* Device Header Banner */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-1 gap-2 border-b border-slate-200/60">
          <div className="flex items-center gap-2.5">
            <div className={`w-2.5 h-2.5 rounded-full ${index % 2 === 0 ? 'bg-amber-500' : 'bg-blue-500'} animate-pulse`} />
            <h3 className="font-bold text-slate-900 text-sm tracking-tight flex items-center gap-2">
              <span>{hive.name || `Device #${index + 1}`}</span>
              <span className="text-xs font-mono font-medium text-slate-500 bg-slate-100 px-1.5 py-0.5 rounded">
                Node: {devId}
              </span>
            </h3>
            <span className="text-xs text-slate-400 hidden md:inline">· {locName}</span>
          </div>

          <div className="flex items-center gap-2">
            <span className={`text-xs font-semibold px-2 py-0.5 rounded-md border ${condInfo.badgeClass}`}>
              {condInfo.label}
            </span>
            <span className={`text-[11px] font-mono px-2 py-0.5 rounded border flex items-center gap-1.5 ${watchdog.badgeClass}`}>
              <span className={`w-1.5 h-1.5 rounded-full ${watchdog.dotClass}`} />
              <span>{watchdog.label}</span>
            </span>
            {onNavigate && (
              <button
                onClick={() => onNavigate('hives')}
                className="text-xs font-semibold text-amber-700 hover:text-amber-800 flex items-center gap-0.5 ml-2 cursor-pointer"
              >
                <span>Hive Details</span>
                <ArrowUpRight className="w-3.5 h-3.5" />
              </button>
            )}
          </div>
        </div>

        {/* Main Grid: Telemetry Time Series (2 cols) + Hardware Node Panel (1 col) */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 sm:gap-6 min-w-0">
          {/* Trend Chart (2 columns) */}
          <div className="bg-white p-3 sm:p-5 rounded-xl border border-slate-200/90 shadow-2xs lg:col-span-2 space-y-4 min-w-0">
            <div className="flex flex-wrap items-center justify-between pb-3 border-b border-slate-100 gap-2">
              <div>
                <h4 className="font-semibold text-slate-900 text-sm flex items-center gap-2">
                  <Activity className="w-4 h-4 text-slate-600" />
                  <span>Telemetry Time Series · {hive.name || devId}</span>
                </h4>
                <p className="text-xs text-slate-400">
                  {timeRange === '24h' ? '24-Hour diurnal cycle trend'
                    : timeRange === '7d' ? '7-Day weekly macro trend'
                    : '30-Day monthly trend'} ({devTemp} · {devHum} · {devFreq})
                </p>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                {/* Time-Range Filter Tabs (matching mobile app: 24 Hours | 7 Days | 30 Days) */}
                <div className="flex items-center bg-slate-100 p-0.5 rounded-lg border border-slate-200">
                  {[
                    { id: '24h', label: '24 Hours' },
                    { id: '7d', label: '7 Days' },
                    { id: '30d', label: '30 Days' }
                  ].map((r) => (
                    <button
                      key={r.id}
                      type="button"
                      onClick={() => setTimeRange(r.id)}
                      className={`px-2.5 py-0.5 text-[11px] font-semibold rounded transition cursor-pointer ${
                        timeRange === r.id
                          ? 'bg-white text-slate-900 shadow-2xs font-bold'
                          : 'text-slate-500 hover:text-slate-800'
                      }`}
                      title={`Filter to last ${r.label}`}
                    >
                      {r.label}
                    </button>
                  ))}
                </div>

                <span className="text-[11px] font-mono bg-slate-50 text-slate-600 border border-slate-200 px-2 py-0.5 rounded shrink-0">
                  DHT22 + INMP441
                </span>
              </div>
            </div>

            <div className="h-64 w-full min-w-0">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart 
                  data={pts}
                  margin={{ top: 5, right: 10, left: -20, bottom: 0 }}
                >
                  <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" vertical={false} />
                  <XAxis dataKey="time" stroke="#94a3b8" fontSize={11} tickLine={false} />
                  <YAxis stroke="#94a3b8" fontSize={11} tickLine={false} axisLine={false} />
                  <Tooltip 
                    contentStyle={{ 
                      backgroundColor: '#0f172a', 
                      borderRadius: '8px', 
                      border: 'none', 
                      color: '#fff', 
                      fontSize: '11px',
                      padding: '8px 12px'
                    }}
                  />
                  <Legend wrapperStyle={{ fontSize: '11px', paddingTop: '10px' }} />
                  <Line type="monotone" dataKey="temp" name="Temperature (°C)" stroke="#d97706" strokeWidth={1.75} dot={false} activeDot={{ r: 4 }} />
                  <Line type="monotone" dataKey="humidity" name="Humidity (%)" stroke="#2563eb" strokeWidth={1.75} dot={false} activeDot={{ r: 4 }} />
                  <Line type="monotone" dataKey="freq" name="Frequency (Hz)" stroke="#7c3aed" strokeWidth={1.75} dot={false} activeDot={{ r: 4 }} />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* Hardware Status Node Panel (1 column) */}
          <div className="bg-white p-4 sm:p-5 rounded-xl border border-slate-200/90 shadow-2xs space-y-4 min-w-0">
            <div className="flex items-center justify-between pb-3 border-b border-slate-100">
              <h4 className="font-semibold text-slate-900 text-sm flex items-center gap-2">
                <Radio className="w-4 h-4 text-slate-600" />
                <span>Node {devId}</span>
              </h4>
              <span className={`text-[11px] font-mono px-2 py-0.5 rounded border flex items-center gap-1.5 ${watchdog.badgeClass}`}>
                <span className={`w-1.5 h-1.5 rounded-full ${watchdog.dotClass}`} />
                <span>{watchdog.label}</span>
              </span>
            </div>

            <div className="space-y-3 text-xs">
              <div className="flex items-center justify-between py-1.5 border-b border-slate-50">
                <span className="text-slate-500 flex items-center gap-1.5">
                  <Wifi className="w-3.5 h-3.5 text-slate-400" />
                  <span>Signal Strength</span>
                </span>
                <span className="font-mono font-medium text-slate-800">
                  {rssi} dBm
                </span>
              </div>

              <div className="flex items-center justify-between py-1.5 border-b border-slate-50">
                <span className="text-slate-500 flex items-center gap-1.5">
                  <Zap className="w-3.5 h-3.5 text-slate-400" />
                  <span>Power Source</span>
                </span>
                <span className="font-mono font-medium text-slate-800">
                  {power}
                </span>
              </div>

              <div className="flex items-center justify-between py-1.5 border-b border-slate-50">
                <span className="text-slate-500 flex items-center gap-1.5">
                  <Layers className="w-3.5 h-3.5 text-slate-400" />
                  <span>Firmware Build</span>
                </span>
                <span className="font-mono font-medium text-slate-800">v2.0.0 (Release)</span>
              </div>

              <div className="flex items-center justify-between py-1.5 border-b border-slate-50">
                <span className="text-slate-500 flex items-center gap-1.5">
                  <Activity className="w-3.5 h-3.5 text-slate-400" />
                  <span>Hardware Watchdog</span>
                </span>
                <span className="font-mono font-medium text-slate-800">
                  {watchdog.elapsedDesc}
                </span>
              </div>

              <div className="flex items-center justify-between py-1.5">
                <span className="text-slate-500">Last Telemetry</span>
                <span className="font-mono font-medium text-slate-800 font-tabular">
                  {lastSeen}
                </span>
              </div>
            </div>

            {/* Diagnostic notice */}
            <div className="p-3 bg-slate-50 rounded-lg border border-slate-200/80 text-[11px] text-slate-600 flex items-center gap-2">
              <Radio className="w-3.5 h-3.5 text-slate-500 shrink-0" />
              <span>Cycle cooldown active. Next sensor scan in 5 minutes.</span>
            </div>
          </div>
        </div>
      </div>
    );
  };

  return (
    <div className="p-3 sm:p-5 md:p-6 max-w-7xl mx-auto space-y-5 sm:space-y-6 min-w-0">
      {/* 1. Executive Status Banner */}
      <div className="bg-white rounded-xl border border-slate-200/90 p-4 sm:p-5 shadow-2xs flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <span className="text-[11px] font-mono uppercase tracking-wider text-slate-400 font-semibold block mb-0.5">
            Colony Health & Diagnostics · {hasMultipleDevices ? `${activeTelemetryList.length} Nodes Monitored` : 'Single Node'}
          </span>
          <h2 className="text-xl font-bold text-slate-900 tracking-tight flex items-center gap-2">
            <span>Condition: {overallCondition}</span>
            {isOverallAlert ? (
              <AlertTriangle className="w-5 h-5 text-red-600 inline" />
            ) : (
              <CheckCircle2 className="w-5 h-5 text-emerald-600 inline" />
            )}
          </h2>
          <p className="text-xs text-slate-500 mt-0.5">
            {selectedYardFilter === 'ALL' 
              ? 'Hive Overview · Real-time inference'
              : `${selectedYardFilter} · Real-time inference`}
          </p>
        </div>

        <div className="flex items-center gap-6 border-t md:border-t-0 md:border-l border-slate-100 pt-3 md:pt-0 md:pl-6">
          <div>
            <span className="text-[11px] text-slate-400 uppercase tracking-wider font-medium block">
              Health Score
            </span>
            <div className="flex items-baseline gap-1 mt-0.5">
              <span className="text-2xl font-bold font-mono text-slate-900 font-tabular">
                {hasMultipleDevices ? avgHealthScore : (activeTelemetryList[0]?.healthScore || 90)}
              </span>
              <span className="text-xs text-slate-400 font-mono">/100</span>
            </div>
          </div>
          <span className={`text-xs font-semibold px-2.5 py-1 rounded-md border ${
            isOverallAlert 
              ? 'text-red-700 bg-red-50 border-red-200' 
              : 'text-emerald-800 bg-emerald-50 border border-emerald-200'
          }`}>
            {isOverallAlert ? 'Alert Required' : 'Nominal'}
          </span>
        </div>
      </div>

      {/* 2. Primary Telemetry Metrics Row (Dynamic based on selected filter) */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4">
        {/* Acoustic Frequency Metric */}
        <div className="bg-white p-4 rounded-xl border border-slate-200/90 shadow-2xs hover:border-slate-300 transition">
          <div className="flex items-center justify-between text-xs text-slate-500 font-medium">
            <span>Acoustic Frequency</span>
            <Volume2 className="w-4 h-4 text-purple-600" />
          </div>
          <div className="mt-2 flex items-baseline justify-between">
            <span className="text-2xl font-bold font-mono text-slate-900 font-tabular">
              {hasMultipleDevices ? `${avgFreq} Hz` : `${activeTelemetryList[0]?.frequency || 102} Hz`}
            </span>
            <span className={`text-[11px] font-medium px-1.5 py-0.5 rounded ${
              hasMultipleDevices 
                ? 'text-purple-700 bg-purple-50 border border-purple-200' 
                : 'text-emerald-700 bg-emerald-50'
            }`}>
              {selectedYardFilter === 'ALL'
                ? (hasMultipleDevices ? `Hive Avg (${activeTelemetryList.length} Nodes)` : 'Normal')
                : `Location Avg (${activeTelemetryList.length} Nodes)`}
            </span>
          </div>
          <div className="mt-2 text-[11px] text-slate-500 space-y-0.5">
            {hasMultipleDevices ? (
              <>
                <div className="font-mono text-[10.5px] text-slate-700 truncate" title={freqBreakdown}>
                  {freqBreakdown}
                </div>
                <div className="text-[10px] text-slate-400">Baseline: 90–260 Hz worker hum</div>
              </>
            ) : (
              <span className="text-slate-400 block">Baseline: 90–260 Hz worker hum</span>
            )}
          </div>
        </div>

        {/* Temperature Metric */}
        <div className="bg-white p-4 rounded-xl border border-slate-200/90 shadow-2xs hover:border-slate-300 transition">
          <div className="flex items-center justify-between text-xs text-slate-500 font-medium">
            <span>Brood Temperature</span>
            <Thermometer className="w-4 h-4 text-amber-600" />
          </div>
          <div className="mt-2 flex items-baseline justify-between">
            <span className="text-2xl font-bold font-mono text-slate-900 font-tabular">
              {hasMultipleDevices ? `${avgTemp}°C` : `${activeTelemetryList[0]?.temp || 29.2}°C`}
            </span>
            <span className={`text-[11px] font-medium px-1.5 py-0.5 rounded ${
              hasMultipleDevices 
                ? 'text-amber-800 bg-amber-50 border border-amber-200' 
                : 'text-slate-600 bg-slate-100'
            }`}>
              {selectedYardFilter === 'ALL'
                ? (hasMultipleDevices ? `Hive Avg (${activeTelemetryList.length} Nodes)` : 'Optimal')
                : `Location Avg (${activeTelemetryList.length} Nodes)`}
            </span>
          </div>
          <div className="mt-2 text-[11px] text-slate-500 space-y-0.5">
            {hasMultipleDevices ? (
              <>
                <div className="font-mono text-[10.5px] text-slate-700 truncate" title={tempBreakdown}>
                  {tempBreakdown}
                </div>
                <div className="text-[10px] text-slate-400">Target nest range: 32°C–36°C</div>
              </>
            ) : (
              <span className="text-slate-400 block">Target nest range: 32°C–36°C</span>
            )}
          </div>
        </div>

        {/* Humidity Metric */}
        <div className="bg-white p-4 rounded-xl border border-slate-200/90 shadow-2xs hover:border-slate-300 transition">
          <div className="flex items-center justify-between text-xs text-slate-500 font-medium">
            <span>Relative Humidity</span>
            <Droplets className="w-4 h-4 text-blue-600" />
          </div>
          <div className="mt-2 flex items-baseline justify-between">
            <span className="text-2xl font-bold font-mono text-slate-900 font-tabular">
              {hasMultipleDevices ? `${avgHum}%` : `${activeTelemetryList[0]?.humidity || 84.5}%`}
            </span>
            <span className={`text-[11px] font-medium px-1.5 py-0.5 rounded ${
              hasMultipleDevices 
                ? 'text-blue-700 bg-blue-50 border border-blue-200' 
                : 'text-slate-600 bg-slate-100'
            }`}>
              {selectedYardFilter === 'ALL'
                ? (hasMultipleDevices ? `Hive Avg (${activeTelemetryList.length} Nodes)` : 'Ambient')
                : `Location Avg (${activeTelemetryList.length} Nodes)`}
            </span>
          </div>
          <div className="mt-2 text-[11px] text-slate-500 space-y-0.5">
            {hasMultipleDevices ? (
              <>
                <div className="font-mono text-[10.5px] text-slate-700 truncate" title={humBreakdown}>
                  {humBreakdown}
                </div>
                <div className="text-[10px] text-slate-400">Safe ceiling threshold: ≤ 85%</div>
              </>
            ) : (
              <span className="text-slate-400 block">Safe ceiling threshold: ≤ 85%</span>
            )}
          </div>
        </div>

        {/* Users Overview Metric */}
        <div className="bg-white p-4 rounded-xl border border-slate-200/90 shadow-2xs hover:border-slate-300 transition">
          <div className="flex items-center justify-between text-xs text-slate-500 font-medium">
            <span>Users</span>
            <Users className="w-4 h-4 text-slate-400" />
          </div>
          <div className="mt-2 flex items-baseline justify-between">
            <div className="flex items-baseline gap-1.5 font-mono text-2xl font-bold text-slate-900">
              <span>{totalUsersCount}</span>
              <span className="text-xs font-normal text-slate-400">users</span>
            </div>
            {isAdmin ? (
              <button 
                onClick={() => onNavigate('users')}
                className="text-xs font-semibold text-amber-700 hover:text-amber-800 flex items-center gap-0.5 cursor-pointer"
              >
                <span>Manage</span>
                <ArrowUpRight className="w-3.5 h-3.5" />
              </button>
            ) : (
              <button 
                onClick={() => onNavigate('users')}
                className="text-xs font-semibold text-amber-700 hover:text-amber-800 flex items-center gap-0.5 cursor-pointer"
              >
                <span>Directory</span>
                <ArrowUpRight className="w-3.5 h-3.5" />
              </button>
            )}
          </div>
          <span className="text-[11px] text-slate-400 mt-2 block">
            {isAdmin ? `${ownersCount || 2} Owner · ${beekeepersCount || 6} Beekeepers` : `${totalUsersCount} registered operators`}
          </span>
        </div>
      </div>

      {/* 3. Control Bar: Location Filter Tabs + View Mode Toggle */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-2 pt-2 border-b border-slate-200/80">
        {/* Left: Location Filter Tabs */}
        <div className="flex items-center gap-2 overflow-x-auto pb-1 text-xs">
          <span className="text-slate-400 text-[11px] font-medium mr-1 flex items-center gap-1 shrink-0">
            <MapPin className="w-3.5 h-3.5 text-slate-400" />
            <span>Location Filter:</span>
          </span>

          <button
            type="button"
            onClick={() => setSelectedYardFilter('ALL')}
            className={`px-3 py-1.5 rounded-lg font-semibold transition cursor-pointer flex items-center gap-1.5 shrink-0 ${
              selectedYardFilter === 'ALL'
                ? 'bg-slate-900 text-white shadow-xs'
                : 'bg-white text-slate-600 hover:bg-slate-100 border border-slate-200'
            }`}
          >
            <span>All Locations</span>
            <span className={`text-[10px] font-mono px-1.5 py-0.2 rounded-full ${
              selectedYardFilter === 'ALL' ? 'bg-slate-700 text-white' : 'bg-slate-100 text-slate-500'
            }`}>
              {displayDevices.length}
            </span>
          </button>

          {allYards.map(yard => (
            <button
              key={yard}
              type="button"
              onClick={() => setSelectedYardFilter(yard)}
              className={`px-3 py-1.5 rounded-lg font-semibold transition cursor-pointer flex items-center gap-1.5 shrink-0 ${
                selectedYardFilter === yard
                  ? 'bg-slate-900 text-white shadow-xs'
                  : 'bg-white text-slate-600 hover:bg-slate-100 border border-slate-200'
              }`}
            >
              <span>{yard}</span>
              <span className={`text-[10px] font-mono px-1.5 py-0.2 rounded-full ${
                selectedYardFilter === yard ? 'bg-slate-700 text-white' : 'bg-slate-100 text-slate-500'
              }`}>
                {groupedDevices[yard]?.length || 0}
              </span>
            </button>
          ))}
        </div>

        {/* Right: View Mode Toggle (Group by Location vs All Hives Flat) */}
        <div className="flex items-center gap-1 bg-slate-100 p-0.5 rounded-lg border border-slate-200 shrink-0 self-start sm:self-auto">
          <button
            type="button"
            onClick={() => setViewMode('grouped')}
            className={`flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-semibold transition cursor-pointer ${
              viewMode === 'grouped'
                ? 'bg-white text-slate-900 shadow-xs'
                : 'text-slate-500 hover:text-slate-800'
            }`}
            title="Group hives into location containers"
          >
            <Layers className="w-3.5 h-3.5 text-amber-600" />
            <span>Group by Location</span>
          </button>

          <button
            type="button"
            onClick={() => setViewMode('flat')}
            className={`flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-semibold transition cursor-pointer ${
              viewMode === 'flat'
                ? 'bg-white text-slate-900 shadow-xs'
                : 'text-slate-500 hover:text-slate-800'
            }`}
            title="Show all hives in a continuous stream"
          >
            <LayoutList className="w-3.5 h-3.5 text-slate-500" />
            <span>All Hives (Flat)</span>
          </button>
        </div>
      </div>

      {/* 4. Telemetry Feeds Content */}
      {displayDevices.length === 0 ? (
        <div className="bg-white rounded-2xl border border-dashed border-slate-200 p-12 text-center shadow-2xs">
          <div className="w-12 h-12 rounded-xl bg-amber-50 text-amber-600 border border-amber-200/80 flex items-center justify-center mx-auto mb-3">
            <Cpu className="w-6 h-6" />
          </div>
          <h3 className="font-bold text-slate-800 text-base mb-1">No Hives Monitored</h3>
          <p className="text-slate-500 text-xs max-w-sm mx-auto">
            All hives have been removed. Register a hive in the Hives tab or pair a node using the BeeWare mobile app.
          </p>
        </div>
      ) : viewMode === 'grouped' ? (
        /* Grouped by Yard Mode */
        <div className="space-y-8">
          {visibleYards.map(yardName => {
            const hivesInYard = groupedDevices[yardName] || [];
            const isCollapsed = collapsedYards[yardName] === true;

            // Calculate Yard Averages
            const yardTemps = hivesInYard.map(h => {
              const live = telemetryMap[h.deviceId];
              const val = live?.temperature !== undefined ? live.temperature : h.temperature;
              if (val === undefined || val === null || val === '') return null;
              const num = typeof val === 'number' ? val : parseFloat(val.toString().replace(/[^0-9.]/g, ''));
              return isNaN(num) ? null : num;
            }).filter(v => v !== null && v > 0);
            const avgYardTemp = yardTemps.length > 0 ? (yardTemps.reduce((a, b) => a + b, 0) / yardTemps.length).toFixed(1) : null;

            const yardHums = hivesInYard.map(h => {
              const live = telemetryMap[h.deviceId];
              const val = live?.humidity !== undefined ? live.humidity : h.humidity;
              if (val === undefined || val === null || val === '') return null;
              const num = typeof val === 'number' ? val : parseFloat(val.toString().replace(/[^0-9.]/g, ''));
              return isNaN(num) ? null : num;
            }).filter(v => v !== null && v > 0);
            const avgYardHum = yardHums.length > 0 ? (yardHums.reduce((a, b) => a + b, 0) / yardHums.length).toFixed(1) : null;

            const queenCount = hivesInYard.filter(h => {
              const live = telemetryMap[h.deviceId];
              const rawC = live?.conditionLabel || h.conditionLabel || 'Queen Present';
              const rawF = live?.frequency || h.acoustic;
              const info = getConditionInfo(rawC, rawF);
              return !info.isAlert;
            }).length;
            const queenPct = hivesInYard.length > 0 ? Math.round((queenCount / hivesInYard.length) * 100) : 100;

            return (
              <div key={yardName} className="bg-slate-50/60 rounded-2xl border border-slate-200/90 p-3 sm:p-5 shadow-2xs space-y-4 sm:space-y-5 min-w-0">
                {/* Yard Section Header */}
                <div 
                  onClick={() => toggleYardCollapse(yardName)}
                  className="flex flex-col md:flex-row md:items-center justify-between pb-3.5 border-b border-slate-200/70 gap-3 cursor-pointer select-none group"
                >
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-xl bg-amber-100/70 text-amber-900 border border-amber-200 flex items-center justify-center shrink-0 shadow-2xs group-hover:bg-amber-100 transition">
                      <MapPin className="w-5 h-5 text-amber-700" />
                    </div>
                    <div>
                      <div className="flex items-center gap-2 flex-wrap">
                        <h3 className="font-bold text-slate-900 text-sm md:text-base tracking-tight group-hover:text-amber-900 transition">
                          {yardName}
                        </h3>
                        <span className="px-2 py-0.5 text-[11px] font-semibold bg-amber-50 text-amber-900 border border-amber-200 rounded-md">
                          {hivesInYard.length} {hivesInYard.length === 1 ? 'Hive' : 'Hives'}
                        </span>
                      </div>
                      <span className="text-[11px] text-slate-400 font-medium">
                        Physical Location · Tap header to {isCollapsed ? 'expand' : 'collapse'}
                      </span>
                    </div>
                  </div>

                  {/* Yard Metrics Strip & Collapse Button */}
                  <div className="flex items-center gap-2 flex-wrap">
                    {avgYardTemp && avgYardHum && (
                      <span className="text-[11px] font-mono text-slate-700 bg-white border border-slate-200 px-3 py-1 rounded-md font-medium shadow-2xs">
                        Location Averages: {avgYardTemp}°C · {avgYardHum}% Humidity
                      </span>
                    )}

                    <span className={`text-[11px] font-semibold px-2.5 py-1 rounded-md border flex items-center gap-1.5 shadow-2xs ${
                      queenPct === 100
                        ? 'text-emerald-800 bg-emerald-50 border-emerald-200'
                        : 'text-red-700 bg-red-50 border-red-200'
                    }`}>
                      {queenPct === 100 ? (
                        <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
                      ) : (
                        <AlertTriangle className="w-3.5 h-3.5 text-red-600" />
                      )}
                      <span>{queenPct}% Queen Present</span>
                    </span>

                    <button
                      type="button"
                      className="p-1 text-slate-400 hover:text-slate-700 rounded transition"
                      title={isCollapsed ? 'Expand location' : 'Collapse location'}
                    >
                      {isCollapsed ? <ChevronDown className="w-4 h-4" /> : <ChevronUp className="w-4 h-4" />}
                    </button>
                  </div>
                </div>

                {/* Yard Hives Telemetry */}
                {!isCollapsed && (
                  <div className="space-y-6">
                    {hivesInYard.map((hive, idx) => renderDeviceCard(hive, idx))}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      ) : (
        /* All Hives Flat Mode */
        <div className="space-y-8">
          {filteredDevices.map((hive, index) => renderDeviceCard(hive, index))}
        </div>
      )}
    </div>
  );
}
