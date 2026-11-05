import React, { useState, useEffect, useMemo } from 'react';
import { 
  collection, 
  onSnapshot, 
  doc, 
  setDoc, 
  updateDoc, 
  deleteDoc, 
  getDocs,
  query,
  where,
  serverTimestamp 
} from 'firebase/firestore';
import { ref, onValue } from 'firebase/database';
import { db, rtdb } from '../firebase';
import { useAuth } from '../context/AuthContext';
import { 
  Plus, 
  QrCode, 
  Trash2, 
  Cpu, 
  ChevronRight, 
  AlertTriangle,
  MapPin,
  Edit3,
  CheckCircle2,
  Printer,
  ArrowRightLeft,
  FolderPlus
} from 'lucide-react';
import { getNodeWatchdogStatus } from '../utils/heartbeat';
import { getConditionInfo } from '../utils/condition';
import HiveDetailView from './HiveDetailView';

export default function HivesView() {
  const { isAdmin } = useAuth();
  const [hives, setHives] = useState([]);
  const [telemetryMap, setTelemetryMap] = useState({});
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [isNewYardModalOpen, setIsNewYardModalOpen] = useState(false);
  const [selectedQrHive, setSelectedQrHive] = useState(null);
  const [selectedHive, setSelectedHive] = useState(null);
  const [pendingDeleteHive, setPendingDeleteHive] = useState(null);
  const [selectedLocationFilter, setSelectedLocationFilter] = useState('ALL');

  // Yard Rename Modal state
  const [renameModal, setRenameModal] = useState(null); // { oldLoc: string, newLoc: string }
  // Reassign Hive Location Modal state
  const [moveHiveModal, setMoveHiveModal] = useState(null); // { hive: object, newLoc: string }
  const [moveLocationMode, setMoveLocationMode] = useState('');

  // Add Hive form state
  const [hiveName, setHiveName] = useState('');
  const [deviceId, setDeviceId] = useState('BW-013230');
  const [locationSelectMode, setLocationSelectMode] = useState('Toril, Catigan APIARY');
  const [customLocation, setCustomLocation] = useState('');

  // New Yard Quick Modal state
  const [newYardNameInput, setNewYardNameInput] = useState('');

  // 1. Subscribe to Firestore Hives
  useEffect(() => {
    const unsubHives = onSnapshot(collection(db, 'hives'), (snap) => {
      setHives(snap.docs.map(d => ({ id: d.id, ...d.data() })));
    });

    return () => unsubHives();
  }, []);

  // 2. Subscribe to RTDB Telemetry for all devices in fleet
  useEffect(() => {
    const deviceIds = hives.length > 0
      ? Array.from(new Set(hives.map(h => (h.deviceId || 'BW-013230').trim())))
      : ['BW-013230'];

    const unsubs = [];
    deviceIds.forEach(devId => {
      const telemetryRef = ref(rtdb, `telemetry/${devId}`);
      const unsub = onValue(telemetryRef, (snap) => {
        if (snap.exists()) {
          setTelemetryMap(prev => ({ ...prev, [devId]: snap.val() }));
        }
      });
      unsubs.push(unsub);
    });

    return () => {
      unsubs.forEach(u => u());
    };
  }, [hives]);

  // Normalize location names (group default / blank into Toril, Catigan APIARY)
  const normalizeLocation = (loc) => {
    if (!loc || loc.trim() === '' || loc.trim().toLowerCase() === 'apiary box') {
      return 'Toril, Catigan APIARY';
    }
    return loc.trim();
  };

  // Deduplicate hives by deviceId (prefer entries with named/valid labels)
  const displayHives = useMemo(() => {
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

  // Group hives by physical apiary location
  const groupedHives = useMemo(() => {
    const groups = {};
    displayHives.forEach(h => {
      const loc = normalizeLocation(h.location);
      if (!groups[loc]) {
        groups[loc] = [];
      }
      groups[loc].push(h);
    });
    return groups;
  }, [displayHives]);

  const allLocations = Object.keys(groupedHives);

  // Update default location mode when locations change
  useEffect(() => {
    if (allLocations.length > 0 && !allLocations.includes(locationSelectMode) && locationSelectMode !== '__NEW__') {
      setLocationSelectMode(allLocations[0]);
    }
  }, [allLocations]);

  // Filtered location keys
  const visibleLocations = selectedLocationFilter === 'ALL' 
    ? allLocations 
    : allLocations.filter(loc => loc === selectedLocationFilter);

  const handleAddHive = async (e) => {
    e.preventDefault();
    if (!isAdmin || !hiveName) return;

    const id = `hive_${Date.now()}`;
    const cleanDev = deviceId.trim().toUpperCase() || 'BW-013230';
    const finalLocation = locationSelectMode === '__NEW__' 
      ? (customLocation.trim() || 'Toril, Catigan APIARY')
      : locationSelectMode;

    const liveTel = telemetryMap[cleanDev];
    const qrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=500x500&data=%7B%22deviceId%22%3A%22${cleanDev}%22%7D`;

    await setDoc(doc(db, 'hives', id), {
      name: hiveName.trim(),
      deviceId: cleanDev,
      location: finalLocation,
      conditionLabel: liveTel?.conditionLabel || 'Queen Present',
      healthScore: liveTel?.healthScore || 95,
      temperature: liveTel?.temperature ? `${liveTel.temperature}°C` : '29.2°C',
      humidity: liveTel?.humidity ? `${liveTel.humidity}%` : '84.5%',
      acoustic: liveTel?.acoustic || liveTel?.frequency ? `${liveTel.frequency || 102} Hz` : '102 Hz',
      wifiStatus: 'Connected',
      batteryLevel: liveTel?.power_source || 'Plugged In',
      qrCodeUrl: qrUrl,
      updatedAt: serverTimestamp()
    });

    setIsAddModalOpen(false);
    setHiveName('');
    setCustomLocation('');
  };

  const handleCreateNewYardFromFilter = (e) => {
    e.preventDefault();
    if (!newYardNameInput.trim()) return;
    const yardName = newYardNameInput.trim();
    setIsNewYardModalOpen(false);
    setNewYardNameInput('');
    // Open Register Hive modal prefilled with new yard
    setLocationSelectMode('__NEW__');
    setCustomLocation(yardName);
    setIsAddModalOpen(true);
  };

  const handleRenameYardLocation = async (e) => {
    e.preventDefault();
    if (!renameModal || !renameModal.newLoc || !renameModal.newLoc.trim()) return;

    const oldLoc = renameModal.oldLoc;
    const cleanNew = renameModal.newLoc.trim();

    try {
      const targets = hives.filter(h => normalizeLocation(h.location) === oldLoc);
      const updates = targets.map(h => updateDoc(doc(db, 'hives', h.id), { location: cleanNew }));
      await Promise.all(updates);
      setRenameModal(null);
      if (selectedLocationFilter === oldLoc) {
        setSelectedLocationFilter(cleanNew);
      }
    } catch (err) {
      console.error("Error renaming location:", err);
    }
  };

  const handleReassignHiveLocation = async (e) => {
    e.preventDefault();
    if (!moveHiveModal) return;

    const targetLoc = moveLocationMode === '__NEW__'
      ? (moveHiveModal.newLoc || '').trim()
      : moveLocationMode;

    if (!targetLoc) return;

    try {
      await updateDoc(doc(db, 'hives', moveHiveModal.hive.id), {
        location: targetLoc
      });
      setMoveHiveModal(null);
    } catch (err) {
      console.error("Error reassigning hive location:", err);
    }
  };

  const confirmDeleteHive = async () => {
    if (!isAdmin || !pendingDeleteHive) return;
    try {
      await deleteDoc(doc(db, 'hives', pendingDeleteHive.id));
      if (pendingDeleteHive.deviceId) {
        const dev = pendingDeleteHive.deviceId.trim();
        const q = query(collection(db, 'hives'), where('deviceId', '==', dev));
        const snap = await getDocs(q);
        for (const d of snap.docs) {
          if (d.id !== pendingDeleteHive.id) {
            await deleteDoc(d.ref).catch(() => {});
          }
        }
        const qUpper = query(collection(db, 'hives'), where('deviceId', '==', dev.toUpperCase()));
        const snapUpper = await getDocs(qUpper);
        for (const d of snapUpper.docs) {
          if (d.id !== pendingDeleteHive.id) {
            await deleteDoc(d.ref).catch(() => {});
          }
        }
        await deleteDoc(doc(db, 'hives', dev)).catch(() => {});
        await deleteDoc(doc(db, 'hives', dev.toUpperCase())).catch(() => {});
      }
      setPendingDeleteHive(null);
    } catch (e) {
      console.error(e);
    }
  };

  if (selectedHive) {
    return (
      <>
        <HiveDetailView
          hive={selectedHive}
          onBack={() => setSelectedHive(null)}
          onShowQr={(h) => setSelectedQrHive(h)}
        />

        {/* Modal: QR Code Print Sticker */}
        {selectedQrHive && (
          <div className="fixed inset-0 z-50 bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4">
            <div className="bg-white rounded-xl max-w-xs w-full p-6 text-center shadow-xl border border-slate-200 space-y-4">
              <div className="flex justify-between items-center pb-2 border-b border-slate-100">
                <span className="text-[11px] font-mono text-slate-500 uppercase tracking-wider">
                  Box ID Tag
                </span>
                <button onClick={() => setSelectedQrHive(null)} className="text-slate-400 hover:text-slate-700 text-sm font-bold p-1 cursor-pointer">
                  ✕
                </button>
              </div>

              <div className="p-4 bg-white border border-slate-300 rounded-xl inline-block shadow-2xs">
                <img 
                  src={selectedQrHive.qrCodeUrl || `https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=%7B%22deviceId%22%3A%22${selectedQrHive.deviceId}%22%7D`}
                  alt="QR Code"
                  className="w-40 h-40 mx-auto object-contain"
                />
                <span className="text-[11px] font-mono font-bold text-slate-800 block mt-2">
                  {selectedQrHive.name}
                </span>
                <span className="text-[10px] font-mono text-slate-400 block">
                  {selectedQrHive.deviceId}
                </span>
              </div>

              <button
                onClick={() => window.print()}
                className="w-full py-2 bg-slate-900 hover:bg-slate-800 text-white rounded-lg text-xs font-medium transition shadow-2xs cursor-pointer"
              >
                Print Label Sticker
              </button>
            </div>
          </div>
        )}
      </>
    );
  }

  return (
    <div className="p-3 sm:p-5 md:p-6 max-w-7xl mx-auto space-y-5 sm:space-y-6 min-w-0">
      {/* 1. Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-4 border-b border-slate-200/80 gap-3">
        <div>
          <h2 className="text-lg font-bold text-slate-900 tracking-tight">Hives & Node Registry</h2>
          <p className="text-xs text-slate-500">Grouped by apiary location, physical hardware bindings, and QR tagging</p>
        </div>

        {isAdmin && (
          <button
            onClick={() => {
              setLocationSelectMode(allLocations[0] || 'Toril, Catigan APIARY');
              setCustomLocation('');
              setIsAddModalOpen(true);
            }}
            className="flex items-center gap-1.5 px-3.5 py-1.5 bg-slate-900 hover:bg-slate-800 text-white font-medium rounded-lg text-xs transition shadow-2xs cursor-pointer"
          >
            <Plus className="w-3.5 h-3.5" />
            <span>Register Hive</span>
          </button>
        )}
      </div>

      {/* 2. Location Filter Tabs at the Top */}
      <div className="flex flex-wrap items-center gap-2 pb-1 text-xs">
        <span className="text-slate-400 text-[11px] font-medium mr-1 flex items-center gap-1">
          <MapPin className="w-3.5 h-3.5 text-slate-400" />
          <span>Location:</span>
        </span>

        {/* All Hives Tab */}
        <button
          type="button"
          onClick={() => setSelectedLocationFilter('ALL')}
          className={`px-3 py-1.5 rounded-lg font-semibold transition cursor-pointer flex items-center gap-1.5 ${
            selectedLocationFilter === 'ALL'
              ? 'bg-slate-900 text-white shadow-xs'
              : 'bg-white text-slate-600 hover:bg-slate-100 border border-slate-200'
          }`}
        >
          <span>All Hives</span>
          <span className={`text-[10px] font-mono px-1.5 py-0.2 rounded-full ${
            selectedLocationFilter === 'ALL' ? 'bg-slate-700 text-white' : 'bg-slate-100 text-slate-500'
          }`}>
            {displayHives.length}
          </span>
        </button>

        {/* Per-Yard Filter Tabs */}
        {allLocations.map(loc => (
          <button
            key={loc}
            type="button"
            onClick={() => setSelectedLocationFilter(loc)}
            className={`px-3 py-1.5 rounded-lg font-semibold transition cursor-pointer flex items-center gap-1.5 ${
              selectedLocationFilter === loc
                ? 'bg-slate-900 text-white shadow-xs'
                : 'bg-white text-slate-600 hover:bg-slate-100 border border-slate-200'
            }`}
          >
            <span>{loc}</span>
            <span className={`text-[10px] font-mono px-1.5 py-0.2 rounded-full ${
              selectedLocationFilter === loc ? 'bg-slate-700 text-white' : 'bg-slate-100 text-slate-500'
            }`}>
              {groupedHives[loc]?.length || 0}
            </span>
          </button>
        ))}

        {/* + New Location Button */}
        {isAdmin && (
          <button
            type="button"
            onClick={() => setIsNewYardModalOpen(true)}
            className="flex items-center gap-1 px-3 py-1.5 text-amber-900 hover:text-amber-950 bg-amber-50 hover:bg-amber-100 border border-amber-200/90 rounded-lg font-semibold transition shadow-2xs cursor-pointer ml-auto sm:ml-0"
            title="Create a new apiary location"
          >
            <FolderPlus className="w-3.5 h-3.5 text-amber-700" />
            <span>+ New Location</span>
          </button>
        )}
      </div>

      {/* 3. Grouped Location Containers */}
      <div className="space-y-6">
        {displayHives.length === 0 ? (
          <div className="bg-white rounded-2xl border border-dashed border-slate-200 p-12 text-center shadow-2xs">
            <div className="w-12 h-12 rounded-xl bg-amber-50 text-amber-600 border border-amber-200/80 flex items-center justify-center mx-auto mb-3">
              <Cpu className="w-6 h-6" />
            </div>
            <h3 className="font-bold text-slate-800 text-base mb-1">No Hives Registered</h3>
            <p className="text-slate-500 text-xs max-w-sm mx-auto mb-4">
              There are currently no hives in the system. Scan a node with the mobile app or register a new hive.
            </p>
            {isAdmin && (
              <button
                type="button"
                onClick={() => setIsAddModalOpen(true)}
                className="inline-flex items-center gap-1.5 px-4 py-2 bg-amber-500 hover:bg-amber-600 text-black font-semibold text-xs rounded-xl shadow-xs transition cursor-pointer"
              >
                <Plus className="w-4 h-4" />
                <span>Register Hive</span>
              </button>
            )}
          </div>
        ) : (
          visibleLocations.map(locName => {
          const hivesInYard = groupedHives[locName] || [];

          // Calculate yard averages
          const temps = hivesInYard.map(h => {
            const live = telemetryMap[h.deviceId];
            const val = live?.temperature !== undefined ? live.temperature : h.temperature;
            if (val === undefined || val === null || val === '') return null;
            const num = typeof val === 'number' ? val : parseFloat(val.toString().replace(/[^0-9.]/g, ''));
            return isNaN(num) ? null : num;
          }).filter(v => v !== null && v > 0);
          const avgYardTemp = temps.length > 0 ? (temps.reduce((a, b) => a + b, 0) / temps.length).toFixed(1) : null;

          const hums = hivesInYard.map(h => {
            const live = telemetryMap[h.deviceId];
            const val = live?.humidity !== undefined ? live.humidity : h.humidity;
            if (val === undefined || val === null || val === '') return null;
            const num = typeof val === 'number' ? val : parseFloat(val.toString().replace(/[^0-9.]/g, ''));
            return isNaN(num) ? null : num;
          }).filter(v => v !== null && v > 0);
          const avgYardHum = hums.length > 0 ? (hums.reduce((a, b) => a + b, 0) / hums.length).toFixed(1) : null;

          // Health / Queen Presence status
          const totalInYard = hivesInYard.length;
          const queenPresentCount = hivesInYard.filter(h => {
            const live = telemetryMap[h.deviceId];
            const rawC = live?.conditionLabel || h.conditionLabel || 'Queen Present';
            const rawF = live?.frequency || h.acoustic;
            const info = getConditionInfo(rawC, rawF);
            return !info.isAlert;
          }).length;
          const queenPercent = totalInYard > 0 ? Math.round((queenPresentCount / totalInYard) * 100) : 100;

          return (
            <div 
              key={locName} 
              className="bg-white rounded-2xl border border-slate-200/90 p-5 shadow-2xs space-y-4"
            >
              {/* Yard Header Bar */}
              <div className="flex flex-col lg:flex-row lg:items-center justify-between pb-3.5 border-b border-slate-100 gap-3">
                {/* Location Name & Quick Summary */}
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-xl bg-amber-50 text-amber-800 border border-amber-200/80 flex items-center justify-center shrink-0 shadow-2xs">
                    <MapPin className="w-5 h-5 text-amber-700" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2 flex-wrap">
                      <h3 className="font-bold text-slate-900 text-sm md:text-base tracking-tight">
                        {locName}
                      </h3>
                      {isAdmin && (
                        <button
                          type="button"
                          onClick={() => setRenameModal({ oldLoc: locName, newLoc: locName })}
                          className="text-slate-400 hover:text-slate-700 p-1 rounded hover:bg-slate-100 cursor-pointer transition"
                          title="Rename this apiary location"
                        >
                          <Edit3 className="w-3.5 h-3.5" />
                        </button>
                      )}
                      <span className="px-2.5 py-0.5 text-[11px] font-semibold bg-amber-50 text-amber-900 border border-amber-200/80 rounded-md">
                        {hivesInYard.length} {hivesInYard.length === 1 ? 'Hive' : 'Hives'} in this Location
                      </span>
                    </div>
                    <span className="text-[11px] text-slate-400 font-medium">
                      Physical apiary site & cluster management
                    </span>
                  </div>
                </div>

                {/* Yard Environmental Summary, Health Badge & Batch QR */}
                <div className="flex flex-wrap items-center gap-2">
                  {avgYardTemp && avgYardHum && (
                    <span className="text-[11px] font-mono text-slate-700 bg-slate-50 border border-slate-200 px-3 py-1 rounded-md font-medium">
                      Location Averages: {avgYardTemp}°C · {avgYardHum}% Humidity
                    </span>
                  )}

                  <span className={`text-[11px] font-semibold px-2.5 py-1 rounded-md border flex items-center gap-1.5 ${
                    queenPercent === 100
                      ? 'text-emerald-800 bg-emerald-50 border-emerald-200'
                      : 'text-red-700 bg-red-50 border-red-200'
                  }`}>
                    {queenPercent === 100 ? (
                      <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
                    ) : (
                      <AlertTriangle className="w-3.5 h-3.5 text-red-600" />
                    )}
                    <span>{queenPercent}% Queen Present</span>
                  </span>
                </div>
              </div>

              {/* Inner Hive Grid (Side-by-side) */}
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-2 xl:grid-cols-3 gap-5">
                {hivesInYard.map((h) => {
                  const devId = (h.deviceId || 'BW-013230').trim();
                  const live = telemetryMap[devId];

                  const tempRaw = live?.temperature !== undefined ? live.temperature : h.temperature;
                  const temp = tempRaw !== undefined && tempRaw !== null && tempRaw !== ''
                    ? (typeof tempRaw === 'number' || !tempRaw.toString().includes('°') ? `${tempRaw}°C` : tempRaw)
                    : '29.2°C';

                  const humRaw = live?.humidity !== undefined ? live.humidity : h.humidity;
                  const hum = humRaw !== undefined && humRaw !== null && humRaw !== ''
                    ? (typeof humRaw === 'number' || !humRaw.toString().includes('%') ? `${humRaw}%` : humRaw)
                    : '84.5%';

                  const freqRaw = live?.frequency !== undefined ? live.frequency : (live?.acoustic || h.acoustic);
                  const freq = freqRaw !== undefined && freqRaw !== null && freqRaw !== ''
                    ? (typeof freqRaw === 'number' || !freqRaw.toString().includes('Hz') ? `${freqRaw} Hz` : freqRaw)
                    : '102 Hz';

                  const rawCond = live?.conditionLabel || h.conditionLabel || 'Queen Present';
                  const condInfo = getConditionInfo(rawCond, freqRaw);
                  const nodeWatchdog = getNodeWatchdogStatus(live || h);

                  return (
                    <div 
                      key={h.id} 
                      onClick={() => setSelectedHive(h)}
                      className="bg-white rounded-xl border border-slate-200 p-4 shadow-2xs hover:border-amber-400 hover:shadow-md transition-all cursor-pointer space-y-3.5 group relative"
                    >
                      {/* Top Row: Name, Location, Move Yard & Condition */}
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <h4 className="font-bold text-slate-900 text-sm group-hover:text-amber-800 transition-colors">
                            {h.name}
                          </h4>
                          <span className="text-[11px] text-slate-400 block font-medium">
                            {locName}
                          </span>
                        </div>

                        <div className="flex items-center gap-1.5 shrink-0">
                          {isAdmin && (
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                const curLoc = normalizeLocation(h.location);
                                setMoveLocationMode(curLoc);
                                setMoveHiveModal({ hive: h, newLoc: curLoc });
                              }}
                              className="flex items-center gap-1 px-2 py-0.5 text-[10px] font-semibold text-slate-600 hover:text-amber-900 bg-slate-50 hover:bg-amber-50 border border-slate-200 hover:border-amber-200 rounded transition cursor-pointer"
                              title="Reassign this hive to a different apiary location"
                            >
                              <ArrowRightLeft className="w-2.5 h-2.5 text-amber-600" />
                              <span>Move Location</span>
                            </button>
                          )}

                          <span className={`text-[11px] font-semibold px-2 py-0.5 rounded border ${condInfo.badgeClass}`}>
                            {condInfo.label}
                          </span>
                        </div>
                      </div>

                      {/* Hardware Pairing row */}
                      <div className="flex items-center justify-between text-xs py-2 px-2.5 bg-slate-50 rounded-lg border border-slate-100 font-mono">
                        <span className="text-slate-600 flex items-center gap-1.5">
                          <Cpu className="w-3.5 h-3.5 text-slate-400" />
                          <span>Node: {devId}</span>
                        </span>
                        <span className={`text-[10px] font-semibold flex items-center gap-1 px-1.5 py-0.2 rounded border ${nodeWatchdog.badgeClass}`}>
                          <span className={`w-1.5 h-1.5 rounded-full ${nodeWatchdog.dotClass}`} />
                          <span>{nodeWatchdog.label}</span>
                        </span>
                      </div>

                      {/* Telemetry Snapshot Row */}
                      <div className="grid grid-cols-3 gap-2 text-center text-xs py-1">
                        <div className="bg-slate-50/70 p-2 rounded-lg border border-slate-100">
                          <span className="text-[10px] text-slate-400 block font-medium">Temp</span>
                          <span className="font-mono font-bold text-slate-800">{temp}</span>
                        </div>
                        <div className="bg-slate-50/70 p-2 rounded-lg border border-slate-100">
                          <span className="text-[10px] text-slate-400 block font-medium">Humidity</span>
                          <span className="font-mono font-bold text-slate-800">{hum}</span>
                        </div>
                        <div className="bg-slate-50/70 p-2 rounded-lg border border-slate-100">
                          <span className="text-[10px] text-slate-400 block font-medium">Pitch</span>
                          <span className="font-mono font-bold text-purple-700">{freq}</span>
                        </div>
                      </div>

                      {/* Bottom Actions */}
                      <div className="pt-2 border-t border-slate-100 flex items-center justify-between">
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            setSelectedQrHive(h);
                          }}
                          className="flex items-center gap-1.5 px-2.5 py-1 text-xs font-semibold text-slate-700 hover:text-slate-900 bg-white hover:bg-slate-50 border border-slate-200 rounded-md transition shadow-2xs cursor-pointer"
                        >
                          <QrCode className="w-3.5 h-3.5 text-slate-500" />
                          <span>Print QR Sticker</span>
                        </button>

                        <div className="flex items-center gap-2">
                          <span className="text-[11px] font-semibold text-slate-400 group-hover:text-amber-600 transition flex items-center gap-0.5">
                            <span>Inspect</span>
                            <ChevronRight className="w-3.5 h-3.5" />
                          </span>

                          {isAdmin && (
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                setPendingDeleteHive(h);
                              }}
                              className="p-1 text-slate-400 hover:text-red-500 hover:bg-red-50 rounded transition cursor-pointer"
                              title="Remove Hive"
                            >
                              <Trash2 className="w-3.5 h-3.5" />
                            </button>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          );
          })
        )}
      </div>

      {/* Modal: Register Hive */}
      {isAdmin && isAddModalOpen && (
        <div className="fixed inset-0 z-50 bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-xl max-w-sm w-full p-5 shadow-xl border border-slate-200 space-y-4">
            <div className="flex items-center justify-between pb-3 border-b border-slate-100">
              <h3 className="font-bold text-slate-900 text-sm">Register Hive</h3>
              <button onClick={() => setIsAddModalOpen(false)} className="text-slate-400 hover:text-slate-700 text-sm font-bold p-1 cursor-pointer">
                ✕
              </button>
            </div>

            <form onSubmit={handleAddHive} className="space-y-3.5 text-xs">
              <div>
                <label className="block text-slate-600 font-semibold mb-1">Hive Identifier</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Hive 2 - Beta"
                  value={hiveName}
                  onChange={(e) => setHiveName(e.target.value)}
                  className="w-full px-3 py-1.5 border border-slate-200 rounded-lg text-slate-900 focus:border-amber-500 focus:outline-none"
                />
              </div>

              <div>
                <label className="block text-slate-600 font-semibold mb-1">Hardware Device ID</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. BW-08266C"
                  value={deviceId}
                  onChange={(e) => setDeviceId(e.target.value)}
                  className="w-full px-3 py-1.5 border border-slate-200 rounded-lg text-slate-900 focus:border-amber-500 focus:outline-none font-mono"
                />
              </div>

              <div>
                <label className="block text-slate-600 font-semibold mb-1">Apiary Location</label>
                <select
                  value={locationSelectMode}
                  onChange={(e) => {
                    setLocationSelectMode(e.target.value);
                    if (e.target.value !== '__NEW__') {
                      setCustomLocation('');
                    }
                  }}
                  className="w-full px-3 py-1.5 border border-slate-200 rounded-lg text-slate-900 focus:border-amber-500 focus:outline-none bg-white cursor-pointer"
                >
                  {allLocations.map(loc => (
                    <option key={loc} value={loc}>
                      {loc}
                    </option>
                  ))}
                  <option value="__NEW__">+ New Location...</option>
                </select>

                {locationSelectMode === '__NEW__' && (
                  <input
                    type="text"
                    required
                    placeholder="Enter new location (e.g. Laguna Farm — North Apiary)"
                    value={customLocation}
                    onChange={(e) => setCustomLocation(e.target.value)}
                    className="mt-2 w-full px-3 py-1.5 border border-amber-300 rounded-lg text-slate-900 focus:border-amber-500 focus:outline-none bg-amber-50/20"
                    autoFocus
                  />
                )}
              </div>

              <div className="pt-2 flex justify-end gap-2 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setIsAddModalOpen(false)}
                  className="px-3 py-1.5 text-slate-600 hover:bg-slate-100 rounded-lg font-medium transition cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-3.5 py-1.5 bg-slate-900 hover:bg-slate-800 text-white rounded-lg font-semibold transition shadow-2xs cursor-pointer"
                >
                  Save Hive
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: Add New Location */}
      {isNewYardModalOpen && (
        <div className="fixed inset-0 z-50 bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-xl max-w-sm w-full p-5 shadow-xl border border-slate-200 space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-slate-100">
              <h3 className="font-bold text-slate-900 text-sm flex items-center gap-1.5">
                <FolderPlus className="w-4 h-4 text-amber-600" />
                <span>Create New Apiary Location</span>
              </h3>
              <button onClick={() => setIsNewYardModalOpen(false)} className="text-slate-400 hover:text-slate-700 text-sm font-bold p-1 cursor-pointer">
                ✕
              </button>
            </div>

            <form onSubmit={handleCreateNewYardFromFilter} className="space-y-3.5 text-xs">
              <div>
                <label className="block text-slate-600 font-semibold mb-1">New Location Name</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Laguna Farm — North Apiary"
                  value={newYardNameInput}
                  onChange={(e) => setNewYardNameInput(e.target.value)}
                  className="w-full px-3 py-1.5 border border-slate-200 rounded-lg text-slate-900 focus:border-amber-500 focus:outline-none"
                  autoFocus
                />
                <p className="text-[10px] text-slate-400 mt-1">
                  After creating this location, you can register a hive to it or move existing hives into it.
                </p>
              </div>

              <div className="pt-2 flex justify-end gap-2 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setIsNewYardModalOpen(false)}
                  className="px-3 py-1.5 text-slate-600 hover:bg-slate-100 rounded-lg font-medium transition cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-3.5 py-1.5 bg-slate-900 hover:bg-slate-800 text-white rounded-lg font-semibold transition shadow-2xs cursor-pointer"
                >
                  Create & Register Hive
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: Rename Location */}
      {renameModal && (
        <div className="fixed inset-0 z-50 bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-xl max-w-sm w-full p-5 shadow-xl border border-slate-200 space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-slate-100">
              <h3 className="font-bold text-slate-900 text-sm flex items-center gap-1.5">
                <MapPin className="w-4 h-4 text-amber-600" />
                <span>Rename Apiary Location</span>
              </h3>
              <button onClick={() => setRenameModal(null)} className="text-slate-400 hover:text-slate-700 text-sm font-bold p-1 cursor-pointer">
                ✕
              </button>
            </div>

            <form onSubmit={handleRenameYardLocation} className="space-y-3.5 text-xs">
              <div>
                <label className="block text-slate-600 font-semibold mb-1">Location Name</label>
                <input
                  type="text"
                  required
                  value={renameModal.newLoc}
                  onChange={(e) => setRenameModal(prev => ({ ...prev, newLoc: e.target.value }))}
                  className="w-full px-3 py-1.5 border border-slate-200 rounded-lg text-slate-900 focus:border-amber-500 focus:outline-none"
                />
                <p className="text-[10px] text-slate-400 mt-1">
                  This will update the location assignment for all hives grouped inside this location.
                </p>
              </div>

              <div className="pt-2 flex justify-end gap-2 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setRenameModal(null)}
                  className="px-3 py-1.5 text-slate-600 hover:bg-slate-100 rounded-lg font-medium transition cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-3.5 py-1.5 bg-slate-900 hover:bg-slate-800 text-white rounded-lg font-semibold transition shadow-2xs cursor-pointer"
                >
                  Update Location
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: Move Hive to Another Location */}
      {moveHiveModal && (
        <div className="fixed inset-0 z-50 bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-xl max-w-sm w-full p-5 shadow-xl border border-slate-200 space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-slate-100">
              <h3 className="font-bold text-slate-900 text-sm flex items-center gap-1.5">
                <ArrowRightLeft className="w-4 h-4 text-amber-600" />
                <span>Move Hive to Location</span>
              </h3>
              <button onClick={() => setMoveHiveModal(null)} className="text-slate-400 hover:text-slate-700 text-sm font-bold p-1 cursor-pointer">
                ✕
              </button>
            </div>

            <form onSubmit={handleReassignHiveLocation} className="space-y-3.5 text-xs">
              <div className="p-2.5 bg-slate-50 rounded-lg border border-slate-200/80 text-slate-700">
                <span className="font-bold text-slate-900 block">{moveHiveModal.hive.name}</span>
                <span className="text-[10px] text-slate-400 block font-mono">Hardware Node: {moveHiveModal.hive.deviceId}</span>
              </div>

              <div>
                <label className="block text-slate-600 font-semibold mb-1">Target Location</label>
                <select
                  value={moveLocationMode}
                  onChange={(e) => {
                    setMoveLocationMode(e.target.value);
                    if (e.target.value !== '__NEW__') {
                      setMoveHiveModal(prev => ({ ...prev, newLoc: e.target.value }));
                    } else {
                      setMoveHiveModal(prev => ({ ...prev, newLoc: '' }));
                    }
                  }}
                  className="w-full px-3 py-1.5 border border-slate-200 rounded-lg text-slate-900 focus:border-amber-500 focus:outline-none bg-white cursor-pointer"
                >
                  {allLocations.map(loc => (
                    <option key={loc} value={loc}>
                      {loc}
                    </option>
                  ))}
                  <option value="__NEW__">+ New Location...</option>
                </select>

                {moveLocationMode === '__NEW__' && (
                  <input
                    type="text"
                    required
                    placeholder="Enter new location (e.g. Laguna Farm — North Apiary)"
                    value={moveHiveModal.newLoc}
                    onChange={(e) => setMoveHiveModal(prev => ({ ...prev, newLoc: e.target.value }))}
                    className="mt-2 w-full px-3 py-1.5 border border-amber-300 rounded-lg text-slate-900 focus:border-amber-500 focus:outline-none bg-amber-50/20"
                    autoFocus
                  />
                )}
              </div>

              <div className="pt-2 flex justify-end gap-2 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setMoveHiveModal(null)}
                  className="px-3 py-1.5 text-slate-600 hover:bg-slate-100 rounded-lg font-medium transition cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-3.5 py-1.5 bg-slate-900 hover:bg-slate-800 text-white rounded-lg font-semibold transition shadow-2xs cursor-pointer"
                >
                  Save Move
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Confirmation Modal for Deleting Hive */}
      {pendingDeleteHive && (
        <div className="fixed inset-0 z-50 bg-slate-900/50 backdrop-blur-xs flex items-center justify-center p-4 animate-in fade-in duration-150">
          <div className="bg-white rounded-2xl max-w-sm w-full p-6 shadow-2xl border border-slate-200 text-center space-y-4 animate-in zoom-in-95 duration-150">
            <div className="w-10 h-10 mx-auto rounded-full bg-red-50 text-red-600 flex items-center justify-center">
              <AlertTriangle className="w-5 h-5" />
            </div>
            <div className="space-y-1">
              <h3 className="text-base font-bold text-slate-900">Remove Hive from Registry?</h3>
              <p className="text-xs text-slate-500">
                Are you sure you want to remove this hive from the active hive registry?
              </p>
            </div>

            <div className="p-3 bg-slate-50 rounded-xl border border-slate-200/80 text-xs text-slate-800 font-medium">
              <div className="font-bold text-slate-900">{pendingDeleteHive.name}</div>
              <div className="text-[11px] text-slate-400 font-mono mt-0.5">{pendingDeleteHive.deviceId} • {pendingDeleteHive.location || 'Apiary Box'}</div>
            </div>

            <div className="flex items-center justify-center gap-2.5 pt-2">
              <button
                type="button"
                onClick={() => setPendingDeleteHive(null)}
                className="flex-1 px-4 py-2 text-slate-700 hover:bg-slate-100 rounded-lg text-xs font-semibold transition border border-slate-200 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={confirmDeleteHive}
                className="flex-1 px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg text-xs font-semibold transition shadow-sm cursor-pointer"
              >
                Confirm Remove
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
