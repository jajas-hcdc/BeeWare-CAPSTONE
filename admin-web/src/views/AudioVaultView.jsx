import React, { useState, useEffect, useRef, useMemo } from 'react';
import { ref, onValue } from 'firebase/database';
import { collection, onSnapshot } from 'firebase/firestore';
import { rtdb, db } from '../firebase';
import { 
  Play, 
  Pause, 
  Download, 
  Check, 
  Volume2, 
  AlertCircle, 
  Layers, 
  Radio, 
  ChevronDown, 
  VolumeX, 
  Wifi,
  MapPin
} from 'lucide-react';
import { getConditionInfo } from '../utils/condition';
import { getNodeWatchdogStatus } from '../utils/heartbeat';

/**
 * Converts raw 16-bit 16 kHz mono PCM Base64 data from the ESP32
 * into a valid browser-playable WAV Blob with a 44-byte RIFF header.
 */
function pcmBase64ToWavBlob(base64Data, sampleRate = 16000) {
  if (!base64Data) return null;
  try {
    const cleanBase64 = base64Data.trim().replace(/[\r\n\s]/g, '');
    const binaryString = window.atob(cleanBase64);
    const len = binaryString.length;
    const pcmBytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
      pcmBytes[i] = binaryString.charCodeAt(i);
    }

    // Check if already contains RIFF header (0x52, 0x49, 0x46, 0x46)
    if (pcmBytes.length >= 4 &&
        pcmBytes[0] === 0x52 && pcmBytes[1] === 0x49 && pcmBytes[2] === 0x46 && pcmBytes[3] === 0x46) {
      return new Blob([pcmBytes], { type: 'audio/wav' });
    }

    // Prepend standard 44-byte WAV header for 16-bit Mono PCM
    const numChannels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * numChannels * (bitsPerSample / 8);
    const blockAlign = numChannels * (bitsPerSample / 8);
    const dataSize = pcmBytes.length;
    const chunkSize = 36 + dataSize;

    const wavBuffer = new ArrayBuffer(44 + dataSize);
    const view = new DataView(wavBuffer);

    // "RIFF"
    view.setUint32(0, 0x52494646, false);
    view.setUint32(4, chunkSize, true);
    // "WAVE"
    view.setUint32(8, 0x57415645, false);
    // "fmt "
    view.setUint32(12, 0x666d7420, false);
    view.setUint32(16, 16, true); // Subchunk1Size
    view.setUint16(20, 1, true);  // AudioFormat (1 = PCM)
    view.setUint16(22, numChannels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, byteRate, true);
    view.setUint16(32, blockAlign, true);
    view.setUint16(34, bitsPerSample, true);
    // "data"
    view.setUint32(36, 0x64617461, false);
    view.setUint32(40, dataSize, true);

    const wavBytes = new Uint8Array(wavBuffer);
    wavBytes.set(pcmBytes, 44);

    return new Blob([wavBytes], { type: 'audio/wav' });
  } catch (err) {
    console.error("PCM to WAV conversion error:", err);
    return null;
  }
}

export default function AudioVaultView() {
  // Hive selection state
  const [hives, setHives] = useState([]);
  const [discoveredDeviceIds, setDiscoveredDeviceIds] = useState(['BW-013230', 'BW-08266C']);
  const [selectedDeviceId, setSelectedDeviceId] = useState(() => {
    return sessionStorage.getItem('beeware_audiovault_selected_dev') || 'BW-013230';
  });

  // Audio vault state for selected hive
  const [audioSlots, setAudioSlots] = useState([]);
  const [loading, setLoading] = useState(true);
  const [activeSlotKey, setActiveSlotKey] = useState(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [audioCurrentTime, setAudioCurrentTime] = useState(0);
  const [audioDuration, setAudioDuration] = useState(3.0);
  const [verifiedSlots, setVerifiedSlots] = useState({});
  const [playerError, setPlayerError] = useState(null);
  const [selectedTelemetry, setSelectedTelemetry] = useState(null);

  const audioRef = useRef(null);
  const canvasRef = useRef(null);
  const audioCtxRef = useRef(null);
  const analyserRef = useRef(null);
  const animIdRef = useRef(null);
  const currentBlobUrlRef = useRef(null);

  // 1. Subscribe to Firestore Hives collection
  useEffect(() => {
    const unsubHives = onSnapshot(collection(db, 'hives'), (snap) => {
      const list = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      setHives(list);
    });

    return () => unsubHives();
  }, []);

  // 2. Discover all device IDs that have audio history in RTDB
  useEffect(() => {
    const audioRootRef = ref(rtdb, 'audio_history');
    const unsub = onValue(audioRootRef, (snap) => {
      if (snap.exists()) {
        const val = snap.val();
        const keys = Object.keys(val).filter(k => val[k] && typeof val[k] === 'object');
        if (keys.length > 0) {
          setDiscoveredDeviceIds(prev => Array.from(new Set([...prev, ...keys])));
        }
      }
    });

    return () => unsub();
  }, []);

  // 3. Unified combined list of hives strictly reflecting registered fleet
  const combinedHiveList = useMemo(() => {
    const map = new Map();

    // Ingest registered Firestore hives
    hives.forEach(h => {
      const devId = (h.deviceId || h.id || '').trim();
      if (devId) {
        map.set(devId, {
          id: h.id,
          deviceId: devId,
          name: h.name || (devId === 'BW-013230' ? 'Hive 1' : devId === 'BW-08266C' ? 'Hive 2' : `Hive (${devId})`),
          location: h.location || 'Apiary Box',
          queenStatus: h.queenStatus || h.conditionLabel || 'Queen Present'
        });
      }
    });

    return Array.from(map.values());
  }, [hives]);

  // Keep selected device synced when hives are deleted/updated
  useEffect(() => {
    if (combinedHiveList.length > 0) {
      if (!combinedHiveList.some(h => h.deviceId === selectedDeviceId)) {
        setSelectedDeviceId(combinedHiveList[0].deviceId);
      }
    } else {
      setSelectedDeviceId('');
    }
  }, [combinedHiveList, selectedDeviceId]);

  // Current selected hive object
  const currentHive = useMemo(() => {
    return combinedHiveList.find(h => h.deviceId === selectedDeviceId) || combinedHiveList[0];
  }, [combinedHiveList, selectedDeviceId]);

  // Handler to switch hives
  const handleSelectHive = (devId) => {
    if (devId === selectedDeviceId) return;

    // Stop current playback and clean up
    if (audioRef.current) {
      audioRef.current.pause();
    }
    setIsPlaying(false);
    setAudioCurrentTime(0);
    setActiveSlotKey(null);
    setPlayerError(null);

    if (currentBlobUrlRef.current) {
      URL.revokeObjectURL(currentBlobUrlRef.current);
      currentBlobUrlRef.current = null;
    }

    setSelectedDeviceId(devId);
    try {
      sessionStorage.setItem('beeware_audiovault_selected_dev', devId);
    } catch (e) {}
  };

  // 4. Subscribe to RTDB live telemetry for the currently selected hive (for online status & live pitch)
  useEffect(() => {
    if (!selectedDeviceId) return;
    const telRef = ref(rtdb, `telemetry/${selectedDeviceId}`);
    const unsub = onValue(telRef, (snap) => {
      if (snap.exists()) {
        setSelectedTelemetry(snap.val());
      } else {
        setSelectedTelemetry(null);
      }
    });

    return () => unsub();
  }, [selectedDeviceId]);

  // 5. Subscribe to RTDB audio_history for the currently selected hive
  useEffect(() => {
    if (!selectedDeviceId) return;

    setLoading(true);
    const audioRefDb = ref(rtdb, `audio_history/${selectedDeviceId}`);
    const unsub = onValue(audioRefDb, (snapshot) => {
      if (snapshot.exists()) {
        const val = snapshot.val();
        const slots = [];
        Object.keys(val).forEach((k) => {
          const item = val[k];
          if (item && typeof item === 'object') {
            slots.push({
              key: k,
              slot: item.slot !== undefined ? item.slot : k,
              date: item.recorded_date || 'Oct 29, 2026',
              time: item.recorded_time || item.timestamp || 'Recent',
              freq: item.frequency || item.frequency_hz || 94,
              condition: item.condition || 'Queen Present',
              trigger: item.trigger || 'Cooldown Cycle',
              audioBase64: item.audioBase64 || item.audio_base64 || item.audio || item.audioUrl || '',
              createdAt: item.createdAt || item.created_at || 0
            });
          }
        });
        slots.sort((a, b) => b.createdAt - a.createdAt);
        setAudioSlots(slots);
        if (slots.length > 0) {
          setActiveSlotKey(slots[0].key);
        } else {
          setActiveSlotKey(null);
        }
      } else {
        setAudioSlots([]);
        setActiveSlotKey(null);
      }
      setLoading(false);
    });

    return () => {
      unsub();
      if (currentBlobUrlRef.current) {
        URL.revokeObjectURL(currentBlobUrlRef.current);
        currentBlobUrlRef.current = null;
      }
      if (animIdRef.current) {
        cancelAnimationFrame(animIdRef.current);
      }
    };
  }, [selectedDeviceId]);

  const activeSlot = audioSlots.find(s => s.key === activeSlotKey) || audioSlots[0];
  const dominantFreq = activeSlot?.freq || 140;
  const watchdog = getNodeWatchdogStatus(selectedTelemetry);

  // Real-time canvas drawing loop
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');

    const renderWave = () => {
      // Sync canvas pixel dimensions with CSS display size
      const rect = canvas.getBoundingClientRect();
      const displayW = Math.floor(rect.width || 800);
      const displayH = Math.floor(rect.height || 112);
      if (canvas.width !== displayW || canvas.height !== displayH) {
        canvas.width = displayW;
        canvas.height = displayH;
      }

      const width = canvas.width;
      const height = canvas.height;
      const centerX = width / 2;
      const centerY = height / 2;

      ctx.clearRect(0, 0, width, height);

      // Clean neutral canvas background
      ctx.fillStyle = '#f8fafc';
      ctx.fillRect(0, 0, width, height);

      // Subtle horizontal baseline and amplitude grids
      ctx.strokeStyle = '#e2e8f0';
      ctx.lineWidth = 1;
      for (const yFrac of [0.25, 0.75]) {
        const y = Math.floor(height * yFrac);
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(width, y);
        ctx.stroke();
      }

      // Horizontal center zero-axis
      ctx.strokeStyle = '#cbd5e1';
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      ctx.moveTo(0, centerY);
      ctx.lineTo(width, centerY);
      ctx.stroke();

      // Vertical center guide line marking the centered wave focal axis
      ctx.strokeStyle = '#e2e8f0';
      ctx.setLineDash([3, 3]);
      ctx.beginPath();
      ctx.moveTo(centerX, 8);
      ctx.lineTo(centerX, height);
      ctx.stroke();
      ctx.setLineDash([]);

      // Theme colors based on frequency status
      let primaryStroke, secondaryStroke, echoStroke, fillGradTop, fillGradBottom;
      if (dominantFreq >= 300) {
        // High frequency distress limit
        primaryStroke = isPlaying ? '#dc2626' : '#ef4444';
        secondaryStroke = 'rgba(239, 68, 68, 0.55)';
        echoStroke = 'rgba(239, 68, 68, 0.25)';
        fillGradTop = 'rgba(239, 68, 68, 0.18)';
        fillGradBottom = 'rgba(239, 68, 68, 0.08)';
      } else if (dominantFreq >= 260) {
        // Queen piping agitation
        primaryStroke = isPlaying ? '#d97706' : '#f59e0b';
        secondaryStroke = 'rgba(245, 158, 11, 0.55)';
        echoStroke = 'rgba(245, 158, 11, 0.25)';
        fillGradTop = 'rgba(245, 158, 11, 0.18)';
        fillGradBottom = 'rgba(245, 158, 11, 0.08)';
      } else {
        // Normal worker hum
        primaryStroke = isPlaying ? '#059669' : '#10b981';
        secondaryStroke = 'rgba(16, 185, 129, 0.55)';
        echoStroke = 'rgba(16, 185, 129, 0.25)';
        fillGradTop = 'rgba(16, 185, 129, 0.18)';
        fillGradBottom = 'rgba(16, 185, 129, 0.08)';
      }

      // Center focal pointer triangle
      ctx.fillStyle = primaryStroke;
      ctx.beginPath();
      ctx.moveTo(centerX - 5, 0);
      ctx.lineTo(centerX + 5, 0);
      ctx.lineTo(centerX, 7);
      ctx.closePath();
      ctx.fill();

      // Wave calculation parameters
      const numPoints = 160;
      const pointsTop = [];
      const pointsBottom = [];
      const pointsEcho = [];

      // Wavelength tuned to dominant frequency
      const k = 0.016 + (dominantFreq / 600) * 0.018;
      const speed = isPlaying ? 0.007 : 0.0035;
      const phase = Date.now() * speed;

      let liveData = null;
      if (isPlaying && analyserRef.current) {
        liveData = new Uint8Array(analyserRef.current.fftSize);
        analyserRef.current.getByteTimeDomainData(liveData);
      }

      const maxA = (height / 2) - 14;
      const breathing = isPlaying ? 1.0 : (0.76 + 0.14 * Math.sin(Date.now() * 0.0022));
      const amp = maxA * breathing;

      for (let i = 0; i <= numPoints; i++) {
        const x = (i / numPoints) * width;
        const normX = (x - centerX) / centerX; // -1 at left, 0 in center, +1 at right
        const envelope = Math.exp(-normX * normX * 3.2); // Taper gracefully to zero at boundaries

        let waveDisp = 0;
        if (liveData && liveData.length > 0) {
          const sampleIdx = Math.floor((i / numPoints) * (liveData.length - 1));
          const audioSample = (liveData[sampleIdx] - 128) / 128; // -1 to +1
          const synth = Math.sin(x * k - phase) * 0.3;
          waveDisp = (audioSample * 0.82 + synth) * envelope;
        } else {
          // Acoustic harmonic wave synthesis
          const sin1 = Math.sin(x * k - phase);
          const sin2 = 0.42 * Math.sin(x * k * 2.1 + phase * 1.35);
          const sin3 = 0.22 * Math.cos(x * k * 0.65 - phase * 0.75);
          waveDisp = ((sin1 + sin2 + sin3) / 1.64) * envelope;
        }

        const yTop = centerY - waveDisp * amp;
        const yBottom = centerY + waveDisp * amp * 0.72;
        const yEcho = centerY - Math.sin(x * k * 1.4 - phase * 0.8) * envelope * (amp * 0.48);

        pointsTop.push({ x, y: yTop });
        pointsBottom.push({ x, y: yBottom });
        pointsEcho.push({ x, y: yEcho });
      }

      // 1. Draw smooth translucent volumetric gradient between upper and lower wave
      ctx.beginPath();
      ctx.moveTo(pointsTop[0].x, pointsTop[0].y);
      for (let i = 1; i < pointsTop.length - 1; i++) {
        const xc = (pointsTop[i].x + pointsTop[i + 1].x) / 2;
        const yc = (pointsTop[i].y + pointsTop[i + 1].y) / 2;
        ctx.quadraticCurveTo(pointsTop[i].x, pointsTop[i].y, xc, yc);
      }
      ctx.lineTo(pointsTop[pointsTop.length - 1].x, pointsTop[pointsTop.length - 1].y);

      for (let i = pointsBottom.length - 1; i > 0; i--) {
        const xc = (pointsBottom[i].x + pointsBottom[i - 1].x) / 2;
        const yc = (pointsBottom[i].y + pointsBottom[i - 1].y) / 2;
        ctx.quadraticCurveTo(pointsBottom[i].x, pointsBottom[i].y, xc, yc);
      }
      ctx.closePath();

      const grad = ctx.createLinearGradient(0, centerY - amp, 0, centerY + amp);
      grad.addColorStop(0, fillGradTop);
      grad.addColorStop(0.5, 'rgba(255, 255, 255, 0.05)');
      grad.addColorStop(1, fillGradBottom);
      ctx.fillStyle = grad;
      ctx.fill();

      // 2. Draw harmonic echo wave (subtle ambient depth)
      ctx.beginPath();
      ctx.moveTo(pointsEcho[0].x, pointsEcho[0].y);
      for (let i = 1; i < pointsEcho.length - 1; i++) {
        const xc = (pointsEcho[i].x + pointsEcho[i + 1].x) / 2;
        const yc = (pointsEcho[i].y + pointsEcho[i + 1].y) / 2;
        ctx.quadraticCurveTo(pointsEcho[i].x, pointsEcho[i].y, xc, yc);
      }
      ctx.lineTo(pointsEcho[pointsEcho.length - 1].x, pointsEcho[pointsEcho.length - 1].y);
      ctx.strokeStyle = echoStroke;
      ctx.lineWidth = 1.2;
      ctx.stroke();

      // 3. Draw secondary lower wave contour
      ctx.beginPath();
      ctx.moveTo(pointsBottom[0].x, pointsBottom[0].y);
      for (let i = 1; i < pointsBottom.length - 1; i++) {
        const xc = (pointsBottom[i].x + pointsBottom[i + 1].x) / 2;
        const yc = (pointsBottom[i].y + pointsBottom[i + 1].y) / 2;
        ctx.quadraticCurveTo(pointsBottom[i].x, pointsBottom[i].y, xc, yc);
      }
      ctx.lineTo(pointsBottom[pointsBottom.length - 1].x, pointsBottom[pointsBottom.length - 1].y);
      ctx.strokeStyle = secondaryStroke;
      ctx.lineWidth = 1.5;
      ctx.stroke();

      // 4. Draw primary upper wave contour
      ctx.beginPath();
      ctx.moveTo(pointsTop[0].x, pointsTop[0].y);
      for (let i = 1; i < pointsTop.length - 1; i++) {
        const xc = (pointsTop[i].x + pointsTop[i + 1].x) / 2;
        const yc = (pointsTop[i].y + pointsTop[i + 1].y) / 2;
        ctx.quadraticCurveTo(pointsTop[i].x, pointsTop[i].y, xc, yc);
      }
      ctx.lineTo(pointsTop[pointsTop.length - 1].x, pointsTop[pointsTop.length - 1].y);
      ctx.strokeStyle = primaryStroke;
      ctx.lineWidth = 2.2;
      ctx.stroke();

      animIdRef.current = requestAnimationFrame(renderWave);
    };

    renderWave();

    return () => {
      if (animIdRef.current) cancelAnimationFrame(animIdRef.current);
    };
  }, [isPlaying, dominantFreq]);

  // Hook Web Audio API Analyser on playback
  useEffect(() => {
    if (isPlaying && audioRef.current && !audioCtxRef.current) {
      try {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext;
        const audioCtx = new AudioContextClass();
        const analyser = audioCtx.createAnalyser();
        analyser.fftSize = 256;
        analyser.smoothingTimeConstant = 0.8;

        const source = audioCtx.createMediaElementSource(audioRef.current);
        source.connect(analyser);
        analyser.connect(audioCtx.destination);

        audioCtxRef.current = audioCtx;
        analyserRef.current = analyser;
      } catch (err) {
        console.warn("Web Audio API link notice:", err);
      }
    }

    if (audioCtxRef.current && audioCtxRef.current.state === 'suspended' && isPlaying) {
      audioCtxRef.current.resume();
    }
  }, [isPlaying]);

  const handlePlayAudio = (slot) => {
    setPlayerError(null);

    if (!slot.audioBase64) {
      setPlayerError(`Slot #${slot.slot} does not contain audio data.`);
      return;
    }

    if (activeSlotKey === slot.key && isPlaying) {
      audioRef.current?.pause();
      setIsPlaying(false);
      return;
    }

    setActiveSlotKey(slot.key);
    setAudioCurrentTime(0);

    const wavBlob = pcmBase64ToWavBlob(slot.audioBase64, 16000);
    if (!wavBlob) {
      setPlayerError("Failed to decode WAV audio from this recording.");
      return;
    }

    if (currentBlobUrlRef.current) {
      URL.revokeObjectURL(currentBlobUrlRef.current);
    }

    const audioUrl = URL.createObjectURL(wavBlob);
    currentBlobUrlRef.current = audioUrl;

    if (audioRef.current) {
      audioRef.current.src = audioUrl;
      audioRef.current.load();
      audioRef.current.play()
        .then(() => {
          setIsPlaying(true);
        })
        .catch(err => {
          console.error("Playback error:", err);
          setIsPlaying(false);
          setPlayerError("Audio playback error. Click again to retry.");
        });
    }
  };

  const handleTimeUpdate = () => {
    if (audioRef.current) {
      setAudioCurrentTime(audioRef.current.currentTime);
      if (audioRef.current.duration && !isNaN(audioRef.current.duration)) {
        setAudioDuration(audioRef.current.duration);
      }
    }
  };

  const handleScrubberClick = (e) => {
    if (!audioRef.current || !audioDuration) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const clickX = e.clientX - rect.left;
    const ratio = Math.max(0, Math.min(1, clickX / rect.width));
    const newTime = ratio * audioDuration;
    audioRef.current.currentTime = newTime;
    setAudioCurrentTime(newTime);
  };

  const handleDownloadWav = (slot) => {
    if (!slot.audioBase64) return;
    const wavBlob = pcmBase64ToWavBlob(slot.audioBase64, 16000);
    if (!wavBlob) return;

    const url = URL.createObjectURL(wavBlob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `beeware_${selectedDeviceId}_slot_${slot.slot}_${slot.freq}Hz.wav`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const toggleGroundTruth = (key) => {
    const slotKey = `${selectedDeviceId}_${key}`;
    setVerifiedSlots(prev => ({
      ...prev,
      [slotKey]: !prev[slotKey]
    }));
  };

  return (
    <div className="p-3 sm:p-5 md:p-6 max-w-7xl mx-auto space-y-5 sm:space-y-6 min-w-0">
      <audio 
        ref={audioRef} 
        onTimeUpdate={handleTimeUpdate} 
        onEnded={() => {
          setIsPlaying(false);
          setAudioCurrentTime(audioDuration);
        }} 
      />

      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-4 border-b border-slate-200/80 gap-3">
        <div>
          <h2 className="text-lg font-bold text-slate-900 tracking-tight">Acoustic Vault & Signal Inspector</h2>
          <p className="text-xs text-slate-500">Continuous 3.0s WAV audio clips from INMP441 microphone ring buffer</p>
        </div>

        <div className="flex items-center gap-2">
          <span className="text-[11px] font-mono text-slate-500 bg-slate-100 border border-slate-200 px-2.5 py-1 rounded-md">
            I2S DMA · 16,000 Hz · PCM 16-bit
          </span>
        </div>
      </div>

      {/* Hive Selector Navigation Strip */}
      <div className="bg-white rounded-xl border border-slate-200/90 p-3 sm:p-4 shadow-2xs space-y-3">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <Layers className="w-4 h-4 text-amber-600 shrink-0" />
            <span className="text-xs font-bold text-slate-800 uppercase tracking-wider">
              Select Hive to Inspect:
            </span>
            <span className="text-[11px] text-slate-400 hidden md:inline">
              ({combinedHiveList.length} {combinedHiveList.length === 1 ? 'Hive Node' : 'Hive Nodes'} Registered)
            </span>
          </div>

          {/* Quick Dropdown Selector for Compact/Mobile view */}
          <div className="flex items-center gap-2 self-start sm:self-auto">
            <span className="text-xs text-slate-400 font-medium hidden sm:inline">Active Hive:</span>
            <div className="relative">
              <select
                value={selectedDeviceId}
                onChange={(e) => handleSelectHive(e.target.value)}
                className="appearance-none pl-3 pr-8 py-1.5 bg-slate-50 hover:bg-slate-100 border border-slate-200 rounded-lg text-xs font-semibold text-slate-800 focus:outline-none focus:ring-2 focus:ring-amber-500 transition cursor-pointer shadow-2xs"
                title="Switch Hive"
              >
                {combinedHiveList.map((h) => (
                  <option key={h.deviceId} value={h.deviceId}>
                    {h.name} ({h.deviceId})
                  </option>
                ))}
              </select>
              <ChevronDown className="w-3.5 h-3.5 text-slate-400 absolute right-2.5 top-1/2 -translate-y-1/2 pointer-events-none" />
            </div>
          </div>
        </div>

        {/* Interactive Hive Cards/Pills Strip */}
        <div className="flex items-center gap-2 overflow-x-auto pb-1 pt-0.5">
          {combinedHiveList.map((h) => {
            const isSelected = h.deviceId === selectedDeviceId;
            return (
              <button
                key={h.deviceId}
                type="button"
                onClick={() => handleSelectHive(h.deviceId)}
                className={`flex items-center gap-2.5 px-3.5 py-2 rounded-xl text-xs font-medium border transition cursor-pointer shrink-0 text-left ${
                  isSelected 
                    ? 'bg-slate-900 text-white border-slate-900 shadow-xs' 
                    : 'bg-slate-50/70 hover:bg-slate-100 text-slate-700 border-slate-200/90'
                }`}
              >
                <div className={`w-2 h-2 rounded-full shrink-0 ${isSelected ? 'bg-amber-400' : 'bg-slate-300'}`} />
                <div className="flex flex-col leading-tight">
                  <div className="flex items-center gap-1.5">
                    <span className="font-bold">{h.name}</span>
                    <span className={`text-[10px] font-mono px-1.5 py-0.2 rounded ${
                      isSelected ? 'bg-slate-800 text-slate-200 border border-slate-700' : 'bg-white text-slate-600 border border-slate-200'
                    }`}>
                      {h.deviceId}
                    </span>
                  </div>
                  <span className={`text-[10px] truncate max-w-[140px] mt-0.5 ${isSelected ? 'text-slate-400' : 'text-slate-400'}`}>
                    {h.location}
                  </span>
                </div>
              </button>
            );
          })}
        </div>

        {/* Selected Hive Summary Bar */}
        <div className="flex flex-wrap items-center justify-between pt-2 border-t border-slate-100 text-xs text-slate-600 gap-2">
          <div className="flex items-center gap-2">
            <span className="text-slate-400">Viewing Vault For:</span>
            <span className="font-bold text-slate-900">{currentHive?.name}</span>
            <span className="font-mono text-slate-600 bg-slate-100 px-2 py-0.5 rounded text-[11px] border border-slate-200">
              Node: {selectedDeviceId}
            </span>
            <span className="text-slate-400 hidden sm:inline">•</span>
            <span className="text-slate-500 hidden sm:inline flex items-center gap-1">
              <MapPin className="w-3 h-3 text-slate-400 inline" />
              {currentHive?.location}
            </span>
          </div>

          <div className="flex items-center gap-2 font-mono text-[11px]">
            <span className={`flex items-center gap-1 px-2 py-0.5 rounded border ${watchdog.badgeClass}`}>
              <span className={`w-1.5 h-1.5 rounded-full ${watchdog.dotClass}`} />
              <span>{watchdog.label}</span>
            </span>
            <span className="text-slate-400">·</span>
            <span className="text-slate-600 font-semibold">
              {audioSlots.length} {audioSlots.length === 1 ? 'Clip' : 'Clips'} Available
            </span>
          </div>
        </div>
      </div>

      {playerError && (
        <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-xs font-medium text-red-700 flex items-center gap-2">
          <AlertCircle className="w-4 h-4 shrink-0" />
          <span>{playerError}</span>
        </div>
      )}

      {/* Empty State when selected hive has no audio recordings */}
      {!loading && audioSlots.length === 0 && (
        <div className="bg-white rounded-xl border border-slate-200/90 p-10 text-center shadow-2xs space-y-3">
          <div className="w-12 h-12 mx-auto rounded-full bg-slate-100 text-slate-400 flex items-center justify-center">
            <VolumeX className="w-6 h-6" />
          </div>
          <div className="space-y-1">
            <h3 className="font-bold text-slate-900 text-sm">
              No Audio Recordings for {currentHive?.name || selectedDeviceId}
            </h3>
            <p className="text-xs text-slate-500 max-w-md mx-auto">
              Hardware node <span className="font-mono font-semibold text-slate-700">{selectedDeviceId}</span> has not uploaded 3.0s WAV audio clips to the ring buffer yet.
              When this ESP32 completes an acoustic sampling cycle, recordings will stream here automatically in real time.
            </p>
          </div>
          {combinedHiveList.length > 1 && (
            <div className="pt-2">
              <span className="text-xs text-slate-400 mr-2">Try viewing another hive:</span>
              {combinedHiveList.filter(h => h.deviceId !== selectedDeviceId).map(h => (
                <button
                  key={h.deviceId}
                  type="button"
                  onClick={() => handleSelectHive(h.deviceId)}
                  className="px-2.5 py-1 text-xs font-semibold rounded-md border border-slate-200 bg-slate-50 hover:bg-slate-100 text-slate-700 transition cursor-pointer mx-1"
                >
                  {h.name} ({h.deviceId})
                </button>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Integrated Audio Inspector & Spectrum Analyzer Card */}
      {activeSlot && (
        <div className="bg-white rounded-xl border border-slate-200/90 shadow-2xs overflow-hidden">
          {/* Top: Playback & Timeline Controls */}
          <div className="p-4 border-b border-slate-100 flex flex-col md:flex-row items-center justify-between gap-4 bg-slate-50/60">
            <div className="flex items-center gap-3 w-full md:w-auto">
              <button
                onClick={() => handlePlayAudio(activeSlot)}
                className="w-9 h-9 rounded-lg bg-slate-900 hover:bg-slate-800 text-white flex items-center justify-center transition shrink-0 cursor-pointer shadow-xs"
                title={isPlaying ? "Pause" : "Play recording"}
              >
                {isPlaying ? <Pause className="w-4 h-4 fill-white" /> : <Play className="w-4 h-4 fill-white ml-0.5" />}
              </button>
              <div>
                <div className="text-xs font-semibold text-slate-900 flex items-center gap-1.5 flex-wrap">
                  <span className="text-amber-700 font-bold">{currentHive?.name}</span>
                  <span className="text-slate-300 font-normal">·</span>
                  <span>Slot #{activeSlot.slot}</span>
                  <span className="text-slate-300 font-normal">·</span>
                  <span className="font-mono text-slate-500 font-normal">{activeSlot.date} {activeSlot.time}</span>
                </div>
                <div className="flex items-center gap-2 mt-0.5">
                  <span className="text-[10px] font-mono font-bold text-purple-700 bg-purple-50 border border-purple-200 px-1.5 py-0.2 rounded">
                    {activeSlot.freq} Hz
                  </span>
                  {(() => {
                    const info = getConditionInfo(activeSlot.condition, activeSlot.freq);
                    return (
                      <span className={`text-[10px] font-semibold px-2 py-0.2 rounded border ${info.badgeClass}`}>
                        {info.label}
                      </span>
                    );
                  })()}
                </div>
              </div>
            </div>

            {/* Scrubber / Progress Bar */}
            <div className="flex-1 max-w-md w-full flex items-center gap-2.5 text-xs font-mono text-slate-500">
              <span className="text-[11px] font-tabular w-8 text-right">0:0{Math.floor(audioCurrentTime)}</span>
              <div 
                onClick={handleScrubberClick}
                className="flex-1 h-3 flex items-center cursor-pointer group"
                title="Click to seek"
              >
                <div className="w-full h-1.5 bg-slate-200 rounded-full overflow-hidden group-hover:h-2 transition-all">
                  <div 
                    className="h-full bg-slate-900 transition-all duration-75"
                    style={{ width: `${Math.min(100, (audioCurrentTime / (audioDuration || 3)) * 100)}%` }}
                  ></div>
                </div>
              </div>
              <span className="text-[11px] font-tabular w-8">0:0{Math.ceil(audioDuration || 3)}</span>
            </div>

            {/* Action */}
            <div className="flex items-center gap-2 self-end md:self-auto">
              <button
                onClick={() => handleDownloadWav(activeSlot)}
                className="flex items-center gap-1.5 px-3 py-1.5 bg-white hover:bg-slate-50 text-slate-700 rounded-md text-xs font-medium transition border border-slate-200 shadow-2xs cursor-pointer"
                title="Download raw WAV file"
              >
                <Download className="w-3.5 h-3.5 text-slate-500" />
                <span>Download WAV</span>
              </button>
            </div>
          </div>

          {/* Bottom: Centered Acoustic Waveform Visualizer */}
          <div className="p-5 space-y-2.5">
            <div className="flex items-center justify-between text-xs pb-1">
              <div>
                <span className="font-semibold text-slate-900 text-xs tracking-tight">Centered Acoustic Waveform</span>
                <span className="text-[11px] text-slate-400 ml-2">Harmonic Sine Wave • Bilateral Fluid Oscilloscope</span>
              </div>
              <span className="text-[11px] font-mono text-slate-700 bg-slate-100 px-2 py-0.5 rounded border border-slate-200 font-medium flex items-center gap-1.5">
                <span className={`w-2 h-2 rounded-full ${dominantFreq >= 300 ? 'bg-red-500' : dominantFreq >= 260 ? 'bg-amber-500' : 'bg-emerald-500'}`}></span>
                Target Harmonic: {activeSlot.freq} Hz
              </span>
            </div>

            {/* Clean Light-Themed Centered Wave Canvas */}
            <div className="relative">
              <canvas 
                ref={canvasRef} 
                width={800} 
                height={110} 
                className="w-full h-28 rounded-lg border border-slate-200/80 bg-slate-50/70"
              />
            </div>

            {/* Symmetrical Wave Ticks & Diagnostic Legend */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between text-[11px] font-mono text-slate-500 pt-2 border-t border-slate-100 gap-2">
              <div className="flex items-center gap-3">
                <span className="text-slate-400">Left Flank (−Δf)</span>
                <span>•</span>
                <span className="font-semibold text-slate-900 bg-slate-100 px-2 py-0.5 rounded border border-slate-200">
                  ▲ Centered Wave Crest: {activeSlot.freq} Hz
                </span>
                <span>•</span>
                <span className="text-slate-400">Right Flank (+Δf)</span>
              </div>

              <div className="flex items-center gap-3 text-[10px]">
                <span className="flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-emerald-500 inline-block"></span>
                  <span className="text-slate-600">90–260 Hz Normal</span>
                </span>
                <span className="flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-amber-500 inline-block"></span>
                  <span className="text-slate-600">260–300 Hz Piping</span>
                </span>
                <span className="flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-red-500 inline-block"></span>
                  <span className="text-slate-600">&ge;300 Hz Distress</span>
                </span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Recordings Table for Selected Hive */}
      {audioSlots.length > 0 && (
        <div className="bg-white rounded-xl border border-slate-200/90 shadow-2xs overflow-hidden">
          <div className="px-5 py-3 border-b border-slate-200 bg-slate-50/60 flex items-center justify-between">
            <h3 className="text-xs font-bold text-slate-800 uppercase tracking-wider">
              {currentHive?.name} Ring Buffer Audio Slots
            </h3>
            <span className="text-[11px] font-mono text-slate-500">
              5-Slot Circular Buffer • Device: {selectedDeviceId}
            </span>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs min-w-[580px]">
            <thead className="bg-slate-50/75 border-b border-slate-200 text-slate-500 font-semibold uppercase tracking-wider text-[11px]">
              <tr>
                <th className="py-3 px-5">Recording</th>
                <th className="py-3 px-5">Timestamp</th>
                <th className="py-3 px-5">Dominant Pitch</th>
                <th className="py-3 px-5">AI Classification</th>
                <th className="py-3 px-5 text-right">Ground Truth</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 text-slate-700">
              {loading ? (
                <tr>
                  <td colSpan="5" className="text-center py-8 text-slate-400">
                    Retrieving audio buffer slots for {currentHive?.name || selectedDeviceId}...
                  </td>
                </tr>
              ) : (
                audioSlots.map((slot) => {
                  const isSelected = activeSlotKey === slot.key;
                  const isThisPlaying = isSelected && isPlaying;
                  const slotKey = `${selectedDeviceId}_${slot.key}`;
                  const isVerified = verifiedSlots[slotKey];

                  return (
                    <tr 
                      key={slot.key} 
                      className={`transition ${isSelected ? 'bg-amber-50/40' : 'hover:bg-slate-50/60'}`}
                    >
                      <td className="py-3.5 px-5">
                        <div className="flex items-center gap-3">
                          <button
                            onClick={() => handlePlayAudio(slot)}
                            className={`flex items-center justify-center w-7 h-7 rounded text-xs font-semibold transition border cursor-pointer ${
                              isThisPlaying
                                ? 'bg-amber-500 text-slate-950 border-amber-600 shadow-xs'
                                : 'bg-white hover:bg-slate-50 text-slate-700 border-slate-200'
                            }`}
                            title={isThisPlaying ? "Pause" : "Play recording"}
                          >
                            {isThisPlaying ? <Pause className="w-3.5 h-3.5" /> : <Play className="w-3.5 h-3.5 ml-0.5" />}
                          </button>
                          <span className="font-semibold text-slate-900">Slot #{slot.slot}</span>
                        </div>
                      </td>

                      <td className="py-3.5 px-5 font-mono text-slate-600">
                        {slot.date} · {slot.time}
                      </td>

                      <td className="py-3.5 px-5 font-mono font-semibold text-purple-700">
                        {slot.freq} Hz
                      </td>

                      <td className="py-3.5 px-5">
                        {(() => {
                          const info = getConditionInfo(slot.condition, slot.freq);
                          return (
                            <span className={`inline-block px-2 py-0.5 rounded text-[11px] font-semibold border ${info.badgeClass}`}>
                              {info.label}
                            </span>
                          );
                        })()}
                      </td>

                      <td className="py-3.5 px-5 text-right">
                        <button
                          onClick={() => toggleGroundTruth(slot.key)}
                          className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-md text-[11px] font-medium transition border cursor-pointer ${
                            isVerified
                              ? 'bg-emerald-50 text-emerald-800 border-emerald-300 font-semibold'
                              : 'bg-white hover:bg-slate-50 text-slate-600 border-slate-200'
                          }`}
                        >
                          {isVerified && <Check className="w-3 h-3 text-emerald-600" />}
                          <span>{isVerified ? 'Verified' : 'Verify'}</span>
                        </button>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
          </div>
        </div>
      )}
    </div>
  );
}
