import React, { useState, useEffect, useMemo, useRef } from 'react';
import { ref, onValue, query, limitToLast } from 'firebase/database';
import { rtdb } from '../firebase';
import { useAuth } from '../context/AuthContext';
import { getNodeWatchdogStatus } from '../utils/heartbeat';
import {
  ArrowLeft,
  QrCode,
  Wifi,
  Zap,
  Thermometer,
  Droplets,
  Volume2,
  Play,
  Pause,
  Download,
  Clock,
  AlertTriangle,
  Activity,
  CheckCircle2,
  Sliders,
  ChevronRight,
  ChevronLeft
} from 'lucide-react';
import {
  ResponsiveContainer,
  LineChart,
  Line,
  AreaChart,
  Area,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  ReferenceLine,
  ReferenceArea
} from 'recharts';

/**
 * Converts raw 16-bit 16 kHz mono PCM Base64 data from the ESP32
 * into a browser-playable WAV Blob with a 44-byte RIFF header.
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

    if (pcmBytes.length >= 4 &&
        pcmBytes[0] === 0x52 && pcmBytes[1] === 0x49 && pcmBytes[2] === 0x46 && pcmBytes[3] === 0x46) {
      return new Blob([pcmBytes], { type: 'audio/wav' });
    }

    const numChannels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * numChannels * (bitsPerSample / 8);
    const blockAlign = numChannels * (bitsPerSample / 8);
    const dataSize = pcmBytes.length;
    const chunkSize = 36 + dataSize;

    const wavBuffer = new ArrayBuffer(44 + dataSize);
    const view = new DataView(wavBuffer);

    view.setUint32(0, 0x52494646, false); // "RIFF"
    view.setUint32(4, chunkSize, true);
    view.setUint32(8, 0x57415645, false); // "WAVE"
    view.setUint32(12, 0x666d7420, false); // "fmt "
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true); // PCM
    view.setUint16(22, numChannels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, byteRate, true);
    view.setUint16(32, blockAlign, true);
    view.setUint16(34, bitsPerSample, true);
    view.setUint32(36, 0x64617461, false); // "data"
    view.setUint32(40, dataSize, true);

    const fullBytes = new Uint8Array(wavBuffer);
    fullBytes.set(pcmBytes, 44);

    return new Blob([wavBuffer], { type: 'audio/wav' });
  } catch (err) {
    console.error("Failed to decode PCM Base64 to WAV Blob:", err);
    return null;
  }
}

/**
 * Swipable and Horizontally-Scrollable Chart Container
 * Mirrors the Flutter app's SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true)
 * Supports mouse drag-to-pan, touch swiping, and navigation buttons.
 */
function SwipableChartContainer({ children, dataLength, height = 180 }) {
  const containerRef = useRef(null);
  const [isDragging, setIsDragging] = useState(false);
  const [startX, setStartX] = useState(0);
  const [scrollLeft, setScrollLeft] = useState(0);

  // Automatically anchor at the rightmost (newest) readings on mount/update
  useEffect(() => {
    if (containerRef.current) {
      containerRef.current.scrollLeft = containerRef.current.scrollWidth;
    }
  }, [dataLength]);

  const handleMouseDown = (e) => {
    setIsDragging(true);
    setStartX(e.pageX - containerRef.current.offsetLeft);
    setScrollLeft(containerRef.current.scrollLeft);
  };

  const handleMouseLeave = () => {
    setIsDragging(false);
  };

  const handleMouseUp = () => {
    setIsDragging(false);
  };

  const handleMouseMove = (e) => {
    if (!isDragging) return;
    e.preventDefault();
    const x = e.pageX - containerRef.current.offsetLeft;
    const walk = (x - startX) * 1.6;
    containerRef.current.scrollLeft = scrollLeft - walk;
  };

  const scrollBy = (offset) => {
    if (containerRef.current) {
      containerRef.current.scrollBy({ left: offset, behavior: 'smooth' });
    }
  };

  // Determine dynamic canvas width: minimum 80px per reading so dates have ample breathing room
  const chartWidth = Math.max(750, dataLength * 80);

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between text-[11px] text-slate-500 font-medium">
        <div className="flex items-center gap-1.5">
          <button 
            type="button"
            onClick={() => scrollBy(-250)}
            className="p-1 px-2 rounded border border-slate-200 bg-white hover:bg-slate-50 text-slate-700 transition text-[11px] shadow-2xs"
            title="Pan Left (Earlier readings)"
          >
            ← Earlier
          </button>
          <button 
            type="button"
            onClick={() => scrollBy(250)}
            className="p-1 px-2 rounded border border-slate-200 bg-white hover:bg-slate-50 text-slate-700 transition text-[11px] shadow-2xs"
            title="Pan Right (Latest readings)"
          >
            Latest →
          </button>
        </div>
        <span className="text-slate-400 font-mono text-[10px]">
          Showing latest readings • Swipe or drag right for earlier history
        </span>
      </div>

      <div
        ref={containerRef}
        onMouseDown={handleMouseDown}
        onMouseLeave={handleMouseLeave}
        onMouseUp={handleMouseUp}
        onMouseMove={handleMouseMove}
        className="w-full overflow-x-auto scrollbar-thin scrollbar-thumb-slate-300 scrollbar-track-slate-100 rounded-lg cursor-grab active:cursor-grabbing select-none"
        style={{ scrollBehavior: isDragging ? 'auto' : 'smooth' }}
      >
        <div style={{ width: `${chartWidth}px`, height: `${height}px` }}>
          {children}
        </div>
      </div>
    </div>
  );
}

export default function HiveDetailView({ hive, onBack, onShowQr }) {
  const { isAdmin } = useAuth();
  const [activeTab, setActiveTab] = useState(0); // 0: Overview, 1: Sensors, 2: AI Analysis, 3: History (Admin/Owner only)
  const [telemetry, setTelemetry] = useState(null);
  const [audioClips, setAudioClips] = useState([]);
  const [historyRecords, setHistoryRecords] = useState([]);
  const [timeframe, setTimeframe] = useState('24h'); // '24h', '7d', '30d' (matching mobile app)

  // Audio Playback
  const [activePlayingId, setActivePlayingId] = useState(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [audioUrl, setAudioUrl] = useState(null);
  const audioRef = useRef(new Audio());

  // Touch Swipe navigation for Sub-tabs (Overview <-> Sensors <-> AI Analysis <-> History)
  const touchStartX = useRef(0);
  const touchEndX = useRef(0);

  const deviceId = hive.deviceId || 'BW-013230';

  const tabs = useMemo(() => {
    const list = [
      { id: 0, label: 'Overview', icon: Activity },
      { id: 1, label: 'Sensors', icon: Thermometer },
      { id: 2, label: 'AI Analysis', icon: Volume2 }
    ];
    if (isAdmin) {
      list.push({ id: 3, label: 'History', icon: Clock });
    }
    return list;
  }, [isAdmin]);

  // Keep activeTab within allowed bounds if user permissions change
  useEffect(() => {
    if (!isAdmin && activeTab === 3) {
      setActiveTab(0);
    }
  }, [isAdmin, activeTab]);

  // 1. Subscribe to Live RTDB Telemetry
  useEffect(() => {
    const telRef = ref(rtdb, `telemetry/${deviceId}`);
    const unsubTel = onValue(telRef, (snap) => {
      if (snap.exists()) {
        setTelemetry(snap.val());
      }
    });

    // 2. Subscribe to RTDB Audio Clips matching mobile app
    const audioQuery = ref(rtdb, `audio_history/${deviceId}`);
    const unsubAudio = onValue(audioQuery, (snap) => {
      if (snap.exists()) {
        const val = snap.val();
        const clips = [];
        Object.keys(val).forEach((k) => {
          const item = val[k];
          if (item) {
            clips.push({ id: k, ...item });
          }
        });
        clips.sort((a, b) => (b.epoch || b.createdAt || b.created_at || 0) - (a.epoch || a.createdAt || a.created_at || 0));
        setAudioClips(clips);
      }
    });

    // 3. Subscribe to RTDB Telemetry History (full dataset starting from Oct 13 matching mobile app)
    const histQuery = ref(rtdb, `telemetry_history/${deviceId}`);
    const unsubHist = onValue(histQuery, (snap) => {
      if (snap.exists()) {
        const val = snap.val();
        const records = [];
        Object.keys(val).forEach((k) => {
          const item = val[k];
          if (item) {
            let epoch = item.epoch || item.createdAt || item.created_at || 0;
            if (epoch > 0 && epoch < 1700000000000 && epoch >= 1700000000) {
              epoch *= 1000;
            }
            records.push({
              id: k,
              epoch: epoch,
              timestamp: item.timestamp || item.recorded_time || k,
              recorded_date: item.recorded_date || '',
              temp: parseFloat(item.temperature) || 0,
              humidity: parseFloat(item.humidity) || 0,
              frequency: parseInt(item.frequency || item.frequency_hz) || 0,
              condition: item.conditionLabel || item.condition || 'Queen Present'
            });
          }
        });
        // Strictly sort by epoch chronologically (earliest to newest)
        records.sort((a, b) => a.epoch - b.epoch);
        setHistoryRecords(records);
      }
    });

    return () => {
      unsubTel();
      unsubAudio();
      unsubHist();
      audioRef.current.pause();
    };
  }, [deviceId]);

  // Touch Swipe Handlers for Sub-tabs
  const handleTouchStart = (e) => {
    touchStartX.current = e.targetTouches[0].clientX;
  };

  const handleTouchMove = (e) => {
    touchEndX.current = e.targetTouches[0].clientX;
  };

  const handleTouchEnd = () => {
    if (!touchStartX.current || !touchEndX.current) return;
    const diff = touchStartX.current - touchEndX.current;
    if (diff > 75) {
      // Swiped left -> Next tab
      setActiveTab((prev) => Math.min(tabs.length - 1, prev + 1));
    } else if (diff < -75) {
      // Swiped right -> Previous tab
      setActiveTab((prev) => Math.max(0, prev - 1));
    }
    touchStartX.current = 0;
    touchEndX.current = 0;
  };

  // Telemetry computation & fallbacks
  const currentTemp = telemetry?.temperature !== undefined 
    ? parseFloat(telemetry.temperature) 
    : (parseFloat((hive.temperature || '34.2').replace('°C', '')) || 34.2);
  
  const currentHum = telemetry?.humidity !== undefined 
    ? parseFloat(telemetry.humidity) 
    : (parseFloat((hive.humidity || '64.0').replace('%', '')) || 64.0);

  const rawPitch = telemetry?.acoustic || telemetry?.frequency || hive.acoustic || '150 Hz';
  const pitchHz = parseInt(rawPitch) || 0;

  const rawCondition = telemetry?.conditionLabel || hive.conditionLabel || 'Queen Present';
  const rawHealth = telemetry?.healthScore !== undefined ? parseInt(telemetry.healthScore) : (hive.healthScore || 95);
  const confidence = telemetry?.confidence !== undefined ? parseInt(telemetry.confidence) : (hive.confidence || 95);

  const latestClip = audioClips[0] || null;

  // Sensor state detection
  const isTempNotDetected = currentTemp <= 0 || telemetry?.temperature === '0' || telemetry?.temperature === '0.0';
  const isHumNotDetected = currentHum <= 0 || telemetry?.humidity === '0' || telemetry?.humidity === '0.0';
  const isAcousticNotDetected = pitchHz <= 0 || rawPitch.toLowerCase().includes('not detected');
  const isLowFreqNoBuzz = !isAcousticNotDetected && pitchHz < 35;
  const isAnyNoBuzz = isAcousticNotDetected || isLowFreqNoBuzz;
  const hasSensorNotDetected = isTempNotDetected || isHumNotDetected || isAcousticNotDetected;

  const isLowTempAlert = !isTempNotDetected && currentTemp > 0 && currentTemp <= 25.0;
  const isHighTempAlert = !isTempNotDetected && currentTemp >= 85.0;

  const conditionLabel = isAnyNoBuzz ? 'No Buzz Detected' : rawCondition;
  const healthScore = isAcousticNotDetected ? 0 : rawHealth;

  // Overview contextual descriptions matching Flutter app
  let overviewDesc = 'The colony is queenright and showing normal healthy behavior.';
  let conditionActionDesc = 'Colony Stable. Continue regular routine monitoring.';

  if (isAcousticNotDetected) {
    overviewDesc = 'No buzz detected (0 Hz / Silent). Acoustic activity is absent or microphone is disconnected.';
    conditionActionDesc = 'No Buzz Detected (0 Hz).\nInspect microphone or check hive activity.';
  } else if (isLowFreqNoBuzz) {
    overviewDesc = `Low frequency received (${pitchHz} Hz < 35 Hz). Classified as No Buzz Detected.`;
    conditionActionDesc = `No Buzz Detected (${pitchHz} Hz).\nFrequency is below the 35 Hz bee acoustic range.`;
  } else if (conditionLabel.toLowerCase().includes('absent')) {
    overviewDesc = 'Acoustic frequency indicates Queenless Roar. Urgent frame inspection needed.';
    conditionActionDesc = 'Urgent Intervention Required.\nInspect brood frames for emergency queen cells.';
  } else if (conditionLabel.toLowerCase().includes('rejected')) {
    overviewDesc = 'High agitation buzzing detected. Workers rejecting introduced queen.';
    conditionActionDesc = 'Worker Agitation Detected.\nInspect slow-release cage to prevent queen balling.';
  } else if (conditionLabel.toLowerCase().includes('accepted')) {
    overviewDesc = 'Colony piping harmony confirmed. Queen accepted into hive.';
    conditionActionDesc = 'Colony Harmonious.\nAvoid disturbing brood nest for 5 days.';
  }

  // Audio Playback handler
  const handleTogglePlay = (clip) => {
    if (!clip) return;
    const b64 = clip.audioBase64 || clip.audio || clip.audio_base64;
    if (!b64) {
      alert("No audio waveform buffer found for this slot.");
      return;
    }

    if (isPlaying && activePlayingId === clip.id) {
      audioRef.current.pause();
      setIsPlaying(false);
      setActivePlayingId(null);
      return;
    }

    const wavBlob = pcmBase64ToWavBlob(b64, clip.sample_rate || 16000);
    if (!wavBlob) {
      alert("Failed to decode audio clip.");
      return;
    }

    if (audioUrl) {
      URL.revokeObjectURL(audioUrl);
    }

    const url = URL.createObjectURL(wavBlob);
    setAudioUrl(url);
    audioRef.current.src = url;
    audioRef.current.play().then(() => {
      setIsPlaying(true);
      setActivePlayingId(clip.id);
    }).catch(err => {
      console.error("Playback failed:", err);
      setIsPlaying(false);
      setActivePlayingId(null);
    });

    audioRef.current.onended = () => {
      setIsPlaying(false);
      setActivePlayingId(null);
    };
  };

  // Condition Badge colors
  const getConditionColor = (cond) => {
    const c = (cond || '').toLowerCase();
    if (isAnyNoBuzz || c.includes('absent') || c.includes('no buzz') || c.includes('not detected')) {
      return {
        badge: 'bg-red-50 text-red-700 border-red-200',
        dot: 'bg-red-500',
        stroke: '#ef4444'
      };
    }
    if (c.includes('rejected')) {
      return {
        badge: 'bg-amber-50 text-amber-800 border-amber-200',
        dot: 'bg-amber-500',
        stroke: '#f59e0b'
      };
    }
    if (c.includes('accepted')) {
      return {
        badge: 'bg-sky-50 text-sky-700 border-sky-200',
        dot: 'bg-sky-500',
        stroke: '#0284c7'
      };
    }
    return {
      badge: 'bg-emerald-50 text-emerald-700 border-emerald-200',
      dot: 'bg-emerald-500',
      stroke: '#10b981'
    };
  };

  const currentColors = getConditionColor(conditionLabel);

  // Synchronized historical dataset combining telemetry_history & audio_history
  const syncedHistory = useMemo(() => {
    const map = new Map();

    // 1. Ingest telemetry_history
    historyRecords.forEach((r) => {
      const key = `${r.epoch || r.timestamp}`;
      map.set(key, {
        epoch: r.epoch || 0,
        timestamp: r.timestamp,
        date: r.recorded_date,
        temp: r.temp,
        humidity: r.humidity,
        pitch: r.frequency,
        condition: r.condition
      });
    });

    // 2. Ingest audio_history
    audioClips.forEach((c) => {
      let epoch = c.epoch || c.createdAt || c.created_at || 0;
      if (epoch > 0 && epoch < 1700000000000 && epoch >= 1700000000) {
        epoch *= 1000;
      }
      const key = `${epoch || c.timestamp || c.recorded_time}`;
      if (!map.has(key)) {
        map.set(key, {
          epoch: epoch,
          timestamp: c.timestamp || c.recorded_time || 'Just now',
          date: c.recorded_date || '',
          temp: parseFloat(c.temperature) || currentTemp,
          humidity: parseFloat(c.humidity) || currentHum,
          pitch: parseInt(c.frequency) || pitchHz,
          condition: c.condition || 'Queen Present'
        });
      }
    });

    // Sort strictly chronological
    let sorted = Array.from(map.values()).sort((a, b) => (a.epoch || 0) - (b.epoch || 0));

    if (sorted.length === 0) {
      // Fallback initial dataset if database is blank
      sorted = [
        { timestamp: '12:00 PM', temp: 34.1, humidity: 62.5, pitch: 145 },
        { timestamp: '12:15 PM', temp: 34.3, humidity: 63.0, pitch: 152 },
        { timestamp: '12:30 PM', temp: 34.5, humidity: 63.8, pitch: 150 },
        { timestamp: '12:45 PM', temp: 34.8, humidity: 64.2, pitch: 158 },
        { timestamp: '01:00 PM', temp: 35.0, humidity: 64.9, pitch: 160 },
        { timestamp: '01:15 PM', temp: 34.9, humidity: 64.5, pitch: 155 },
        { timestamp: '01:30 PM', temp: currentTemp, humidity: currentHum, pitch: pitchHz || 150 },
      ];
    }

    // Filter by timeframe: '24h' (24 Hours) | '7d' (7 Days) | '30d' (30 Days) matching mobile app
    const validEpochs = sorted.map(p => p.epoch).filter(Boolean);
    const maxEpoch = validEpochs.length > 0 ? Math.max(...validEpochs) : Date.now();
    let cutoffMs = 24 * 60 * 60 * 1000; // 24 Hours default
    if (timeframe === '7d' || timeframe === '7 Days') cutoffMs = 7 * 24 * 60 * 60 * 1000;
    else if (timeframe === '30d' || timeframe === '30 Days') cutoffMs = 30 * 24 * 60 * 60 * 1000;

    let filtered = sorted.filter(p => (p.epoch || 0) >= (maxEpoch - cutoffMs));
    if (filtered.length < 2) {
      const count = (timeframe === '24h' || timeframe === '24 Hours') ? 12 : ((timeframe === '7d' || timeframe === '7 Days') ? 20 : 30);
      filtered = sorted.slice(-count);
    }

    const shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const isDayView = timeframe === '24h' || timeframe === '24 Hours';

    // Group by calendar day for multi-day 7 Days and 30 Days views
    const dayMap = new Map();
    filtered.forEach(p => {
      const dt = p.epoch ? new Date(p.epoch) : new Date();
      const dayKey = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
      if (!dayMap.has(dayKey)) dayMap.set(dayKey, []);
      dayMap.get(dayKey).push(p);
    });

    const isMultiDay = dayMap.size >= 2;

    if (!isDayView && isMultiDay) {
      // 7 Days & 30 Days with multiple calendar days:
      // Group by calendar day into 1 daily average point per day (matching Flutter app)
      const dayKeys = Array.from(dayMap.keys()).sort();
      return dayKeys.map(dKey => {
        const pts = dayMap.get(dKey);
        const validT = pts.map(x => x.temp).filter(t => t > 0);
        const validH = pts.map(x => x.humidity).filter(h => h > 0);
        const validP = pts.map(x => x.pitch).filter(p => p > 0);

        const avgT = validT.length ? parseFloat((validT.reduce((a, b) => a + b, 0) / validT.length).toFixed(1)) : pts[pts.length - 1].temp;
        const avgH = validH.length ? parseFloat((validH.reduce((a, b) => a + b, 0) / validH.length).toFixed(1)) : pts[pts.length - 1].humidity;
        const avgP = validP.length ? Math.round(validP.reduce((a, b) => a + b, 0) / validP.length) : pts[pts.length - 1].pitch;

        const refDt = pts[pts.length - 1].epoch ? new Date(pts[pts.length - 1].epoch) : new Date(dKey);
        const mon = shortMonths[refDt.getMonth()];
        const day = String(refDt.getDate()).padStart(2, '0');
        const dateLabel = `${mon} ${day}`;

        return {
          epoch: refDt.getTime(),
          timestamp: dateLabel,
          displayDate: dateLabel,
          fullDate: `${mon} ${day}, ${refDt.getFullYear()} (Daily Average)`,
          temp: avgT,
          humidity: avgH,
          pitch: avgP,
          condition: pts[pts.length - 1].condition || 'Queen Present'
        };
      });
    }

    // Single day or 24 Hours view: format individual points
    return filtered.map(p => {
      const dt = p.epoch ? new Date(p.epoch) : null;
      let dateLabel = p.timestamp || 'Recent';
      let fullLabel = p.timestamp || 'Recent';

      if (dt && !isNaN(dt.getTime())) {
        const mon = shortMonths[dt.getMonth()];
        const day = String(dt.getDate()).padStart(2, '0');
        let hr = dt.getHours();
        const ampm = hr >= 12 ? 'PM' : 'AM';
        hr = hr % 12 || 12;
        const min = String(dt.getMinutes()).padStart(2, '0');

        fullLabel = `${mon} ${day}, ${dt.getFullYear()} ${hr}:${min} ${ampm}`;

        if (isDayView) {
          // 24 Hours: display time
          dateLabel = p.timestamp || `${hr}:${min} ${ampm}`;
        } else {
          // 7 Days & 30 Days (when points fall on same day): DISPLAY DATE prominently
          dateLabel = `${mon} ${day} · ${hr}:${min} ${ampm}`;
        }
      } else if (!isDayView && p.date) {
        dateLabel = p.date;
      }

      return {
        ...p,
        displayDate: dateLabel,
        fullDate: fullLabel
      };
    });
  }, [historyRecords, audioClips, timeframe, currentTemp, currentHum, pitchHz]);

  // Averages calculation for badges
  const avgStats = useMemo(() => {
    if (syncedHistory.length === 0) return { temp: '34.0', hum: '64', pitch: '150' };
    const validT = syncedHistory.map(p => p.temp).filter(t => t > 0);
    const validH = syncedHistory.map(p => p.humidity).filter(h => h > 0);
    const validP = syncedHistory.map(p => p.pitch).filter(p => p > 0);

    const avgT = validT.length ? (validT.reduce((a, b) => a + b, 0) / validT.length).toFixed(1) : currentTemp.toFixed(1);
    const avgH = validH.length ? Math.round(validH.reduce((a, b) => a + b, 0) / validH.length) : Math.round(currentHum);
    const avgP = validP.length ? Math.round(validP.reduce((a, b) => a + b, 0) / validP.length) : pitchHz;

    return { temp: avgT, hum: avgH, pitch: avgP };
  }, [syncedHistory, currentTemp, currentHum, pitchHz]);

  // Condition timeline records
  const conditionTimeline = useMemo(() => {
    const list = [];
    syncedHistory.forEach((item) => {
      if (item.condition) {
        const last = list[list.length - 1];
        if (!last || last.condition !== item.condition) {
          list.push({
            date: item.date ? `${item.date}, ${item.timestamp}` : item.timestamp,
            condition: item.condition
          });
        }
      }
    });
    return list.slice(-8).reverse();
  }, [syncedHistory]);

  return (
    <div 
      className="p-3 sm:p-5 md:p-6 max-w-7xl mx-auto space-y-5 animate-in fade-in duration-200 min-w-0"
      onTouchStart={handleTouchStart}
      onTouchMove={handleTouchMove}
      onTouchEnd={handleTouchEnd}
    >
      {/* Top Navigation & Breadcrumbs Bar */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-4 border-b border-slate-200/90 gap-3 sm:gap-4">
        <div className="flex flex-wrap items-center gap-2.5 sm:gap-3">
          <button
            onClick={onBack}
            className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg border border-slate-200 bg-white hover:bg-slate-100 text-slate-700 font-medium text-xs transition shadow-2xs cursor-pointer"
            title="Back to Hives"
          >
            <ArrowLeft className="w-3.5 h-3.5" />
            <span>Back to Hives</span>
          </button>
          <div>
            <div className="flex items-center gap-2 flex-wrap">
              <h2 className="text-lg font-bold text-slate-900 tracking-tight">{hive.name}</h2>
              <span className={`text-[11px] font-semibold px-2 py-0.5 rounded border ${currentColors.badge}`}>
                {conditionLabel}
              </span>
            </div>
            <p className="text-xs text-slate-500 font-mono mt-0.5">
              Node: <span className="font-semibold text-slate-700">{deviceId}</span> • {hive.location || 'Apiary Box'}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2 flex-wrap self-start sm:self-auto">
          {onShowQr && (
            <button
              onClick={() => onShowQr(hive)}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-white hover:bg-slate-50 text-slate-700 border border-slate-200 rounded-lg text-xs font-medium transition shadow-2xs cursor-pointer"
            >
              <QrCode className="w-3.5 h-3.5 text-slate-500" />
              <span>Hive QR Tag</span>
            </button>
          )}
          {(() => {
            const watchdog = getNodeWatchdogStatus(telemetry);
            return (
              <span className={`flex items-center gap-1.5 px-2.5 py-1 text-[11px] font-medium rounded-lg border ${watchdog.badgeClass}`}>
                <Wifi className={`w-3 h-3 ${watchdog.status === 'online' ? 'animate-pulse text-emerald-600' : 'text-slate-400'}`} />
                <span>{watchdog.label} ({watchdog.elapsedDesc})</span>
              </span>
            );
          })()}
        </div>
      </div>

      {/* Sub-tab Navigation (Swipable) */}
      <div className="border-b border-slate-200">
        <nav className="flex space-x-3 sm:space-x-6 overflow-x-auto pb-0.5">
          {tabs.map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center gap-1.5 py-2 px-1 border-b-2 text-xs font-semibold tracking-wide transition-colors ${
                  isActive
                    ? 'border-amber-500 text-amber-700'
                    : 'border-transparent text-slate-500 hover:text-slate-800 hover:border-slate-300'
                }`}
              >
                {Icon && <Icon className="w-3.5 h-3.5" />}
                <span>{tab.label}</span>
              </button>
            );
          })}
        </nav>
      </div>

      {/* Sensor Not Detected Banner */}
      {hasSensorNotDetected && (
        <div className="bg-red-50/90 border border-red-200/90 rounded-xl p-3.5 space-y-1 shadow-2xs">
          <div className="flex items-center gap-2">
            <AlertTriangle className="w-4 h-4 text-red-600 shrink-0" />
            <h4 className="text-xs font-bold text-red-900">Hardware Sensor Alert Detected</h4>
          </div>
          <ul className="text-xs text-red-800 list-disc list-inside space-y-0.5">
            {isTempNotDetected && <li>Temperature sensor not detected (0.0°C) - Check DHT22 GPIO 4</li>}
            {isHumNotDetected && <li>Humidity sensor not detected (0%) - Check DHT22 GPIO 4</li>}
            {isAcousticNotDetected && <li>Acoustic microphone not detected (0 Hz) - Check INMP441 I2S pins</li>}
          </ul>
          <p className="text-[11px] text-red-700 italic">Inspect physical sensor wiring and power on the ESP32 node.</p>
        </div>
      )}

      {/* ================= TAB 0: OVERVIEW ================= */}
      {activeTab === 0 && (
        <div className="space-y-5 animate-in fade-in duration-150">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
            {/* Card 1: AI Colony Health Assessment */}
            <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs space-y-4">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-slate-800 uppercase tracking-wider">
                  AI Colony Health Assessment
                </span>
                <span className="text-[10px] font-mono text-slate-400">Model: SVM/TFLite</span>
              </div>

              <div className="flex items-center gap-5">
                <div className="relative w-24 h-24 flex items-center justify-center shrink-0">
                  <svg className="w-full h-full transform -rotate-90" viewBox="0 0 36 36">
                    <path
                      className="text-slate-100"
                      strokeWidth="3.2"
                      stroke="currentColor"
                      fill="none"
                      d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                    />
                    <path
                      stroke={currentColors.stroke}
                      strokeDasharray={`${healthScore}, 100`}
                      strokeWidth="3.2"
                      strokeLinecap="round"
                      fill="none"
                      d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                    />
                  </svg>
                  <div className="absolute flex flex-col items-center">
                    <span className="text-xl font-bold font-mono text-slate-900">{healthScore}%</span>
                    <span className="text-[8px] font-bold text-slate-400 tracking-wider">SCORE</span>
                  </div>
                </div>

                <div className="space-y-1.5 min-w-0">
                  <h3 className="text-base font-bold text-slate-900 truncate">{conditionLabel}</h3>
                  <p className="text-xs text-slate-600 line-clamp-2 leading-relaxed">{overviewDesc}</p>
                  <div className="flex items-center gap-2 pt-1">
                    <span className="text-[11px] font-mono text-slate-500">
                      Confidence: <strong className="text-slate-800">{isAcousticNotDetected ? '0%' : `${confidence}%`}</strong>
                    </span>
                    {isAnyNoBuzz && (
                      <span className="text-[10px] font-bold text-red-700 bg-red-100 px-1.5 py-0.2 rounded">
                        Silent (0 Hz)
                      </span>
                    )}
                  </div>
                </div>
              </div>
            </div>

            {/* Card 2: Current Colony Condition & Mascot */}
            <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs flex items-center justify-between gap-4">
              <div className="space-y-2.5">
                <span className="text-xs font-bold text-slate-800 uppercase tracking-wider block">
                  Colony Diagnostic Guidance
                </span>
                <span className={`inline-block text-xs font-bold px-2.5 py-1 rounded-md border ${currentColors.badge}`}>
                  {conditionLabel}
                </span>
                <p className="text-xs text-slate-600 whitespace-pre-line leading-relaxed">
                  {conditionActionDesc}
                </p>
              </div>
            </div>
          </div>

          {/* Card 3: Current Live Sensor Telemetry */}
          <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-slate-100">
              <h3 className="text-xs font-bold text-slate-800 uppercase tracking-wider">
                Current Sensor Data Snapshot
              </h3>
              <span className="text-[11px] font-mono text-slate-400">
                Updated: {telemetry?.time || 'Just now'}
              </span>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {/* Temperature */}
              <div className="p-3.5 rounded-lg bg-slate-50/80 border border-slate-100 space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-medium text-slate-500 flex items-center gap-1.5">
                    <Thermometer className="w-3.5 h-3.5 text-amber-600" />
                    <span>Temperature</span>
                  </span>
                  {isLowTempAlert && <span className="text-[10px] text-red-600 font-bold bg-red-100 px-1.5 py-0.2 rounded">Low Temp</span>}
                  {isHighTempAlert && <span className="text-[10px] text-red-600 font-bold bg-red-100 px-1.5 py-0.2 rounded">High Temp</span>}
                </div>
                <div className="flex items-baseline gap-1">
                  <span className={`text-2xl font-bold font-mono ${isLowTempAlert || isHighTempAlert || isTempNotDetected ? 'text-red-600' : 'text-slate-900'}`}>
                    {isTempNotDetected ? '0.0°C' : `${currentTemp.toFixed(1)}°C`}
                  </span>
                </div>
                <div className="w-full bg-slate-200 h-1.5 rounded-full overflow-hidden">
                  <div 
                    className={`h-full ${currentTemp >= 32 && currentTemp <= 36 ? 'bg-emerald-500' : 'bg-amber-500'}`}
                    style={{ width: `${Math.min(100, Math.max(10, (currentTemp / 50) * 100))}%` }}
                  />
                </div>
                <span className="text-[10px] text-slate-400 block font-mono">Optimal: 32.0°C - 36.0°C</span>
              </div>

              {/* Humidity */}
              <div className="p-3.5 rounded-lg bg-slate-50/80 border border-slate-100 space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-medium text-slate-500 flex items-center gap-1.5">
                    <Droplets className="w-3.5 h-3.5 text-blue-600" />
                    <span>Relative Humidity</span>
                  </span>
                  {isHumNotDetected && <span className="text-[10px] text-red-600 font-bold bg-red-100 px-1.5 py-0.2 rounded">Not Detected</span>}
                </div>
                <div className="flex items-baseline gap-1">
                  <span className={`text-2xl font-bold font-mono ${isHumNotDetected ? 'text-red-600' : 'text-slate-900'}`}>
                    {isHumNotDetected ? '0%' : `${currentHum.toFixed(1)}%`}
                  </span>
                </div>
                <div className="w-full bg-slate-200 h-1.5 rounded-full overflow-hidden">
                  <div 
                    className="h-full bg-sky-500"
                    style={{ width: `${Math.min(100, Math.max(10, currentHum))}%` }}
                  />
                </div>
                <span className="text-[10px] text-slate-400 block font-mono">Normal: 50.0% - 70.0%</span>
              </div>

              {/* Acoustic Frequency & Buzz Wave */}
              <div className="p-3.5 rounded-lg bg-slate-50/80 border border-slate-100 space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-medium text-slate-500 flex items-center gap-1.5">
                    <Volume2 className="w-3.5 h-3.5 text-purple-600" />
                    <span>Dominant Acoustic Pitch</span>
                  </span>
                  {latestClip && (
                    <button
                      onClick={() => handleTogglePlay(latestClip)}
                      className="flex items-center gap-1 px-2 py-0.5 rounded bg-purple-100 hover:bg-purple-200 text-purple-800 transition text-[10px] font-semibold"
                      title="Listen to 3s Audio Clip"
                    >
                      {isPlaying && activePlayingId === latestClip.id ? (
                        <>
                          <Pause className="w-2.5 h-2.5" />
                          <span>Pause Audio</span>
                        </>
                      ) : (
                        <>
                          <Play className="w-2.5 h-2.5" />
                          <span>Play 3s Audio</span>
                        </>
                      )}
                    </button>
                  )}
                </div>
                <div className="flex items-baseline gap-1">
                  <span className={`text-2xl font-bold font-mono ${isAnyNoBuzz ? 'text-red-600' : 'text-purple-700'}`}>
                    {isAcousticNotDetected ? '0 Hz' : `${pitchHz} Hz`}
                  </span>
                  <span className="text-[11px] text-slate-400 font-mono">
                    ({isAnyNoBuzz ? 'No Buzz' : 'Active Buzz'})
                  </span>
                </div>
                <div className="flex items-end gap-1 h-3 pt-1">
                  {[20, 60, 90, 45, 100, 70, 30, 85, 40].map((h, i) => (
                    <span 
                      key={i} 
                      className={`flex-1 rounded-full ${isAnyNoBuzz ? 'bg-slate-300' : 'bg-purple-500 animate-pulse'}`}
                      style={{ height: isAnyNoBuzz ? '30%' : `${h}%` }}
                    />
                  ))}
                </div>
                <span className="text-[10px] text-slate-400 block font-mono truncate">
                  {latestClip ? `Recorded: ${latestClip.recorded_time || 'Recent slot'}` : 'INMP441 Microphone'}
                </span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ================= TAB 1: SENSORS ================= */}
      {activeTab === 1 && (
        <div className="space-y-5 animate-in fade-in duration-150">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
            {/* Temperature Detail */}
            <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs space-y-3.5">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-slate-800 uppercase tracking-wider">
                  Temperature Sensor (DHT22)
                </span>
                <span className="text-[10px] font-mono text-slate-400">GPIO 4</span>
              </div>

              <div className="flex items-baseline gap-2">
                <span className={`text-3xl font-bold font-mono ${isLowTempAlert || isHighTempAlert || isTempNotDetected ? 'text-red-600' : 'text-slate-900'}`}>
                  {isTempNotDetected ? '0.0°C' : `${currentTemp.toFixed(1)}°C`}
                </span>
                <span className="text-xs font-semibold text-slate-500">
                  {isLowTempAlert ? 'Low Temp Alert (≤ 25.0°C)' : isHighTempAlert ? 'High Temp Alert (≥ 85.0°C)' : 'Optimal Healthy Range'}
                </span>
              </div>

              <p className="text-xs text-slate-600 leading-relaxed">
                Brood nest thermoregulation target: <strong>32.0°C – 36.0°C</strong>. Worker bees actively fan wings to cool or cluster to warm the brood.
              </p>

              <div className="p-3 bg-slate-50 rounded-lg border border-slate-100 text-[11px] font-mono space-y-1">
                <div className="flex justify-between text-slate-500">
                  <span>Lower Threshold: 25.0°C</span>
                  <span>Optimal: 35.0°C</span>
                  <span>Upper Threshold: 85.0°C</span>
                </div>
              </div>
            </div>

            {/* Relative Humidity Detail */}
            <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs space-y-3.5">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-slate-800 uppercase tracking-wider">
                  Humidity Sensor (DHT22)
                </span>
                <span className="text-[10px] font-mono text-slate-400">GPIO 4</span>
              </div>

              <div className="flex items-baseline gap-2">
                <span className={`text-3xl font-bold font-mono ${isHumNotDetected ? 'text-red-600' : 'text-slate-900'}`}>
                  {isHumNotDetected ? '0%' : `${currentHum.toFixed(1)}%`}
                </span>
                <span className="text-xs font-semibold text-slate-500">
                  {isHumNotDetected ? 'Check DHT22 Data Wire' : 'Normal Range: 50% - 70%'}
                </span>
              </div>

              <p className="text-xs text-slate-600 leading-relaxed">
                Optimal egg hatching and larval development requires humidity between <strong>50% and 70%</strong>. Excessive moisture can foster chalkbrood fungi.
              </p>

              <div className="p-3 bg-slate-50 rounded-lg border border-slate-100 text-[11px] font-mono space-y-1">
                <div className="flex justify-between text-slate-500">
                  <span>Dry Limit: 40%</span>
                  <span>Healthy Target: 60%</span>
                  <span>Max Limit: 80%</span>
                </div>
              </div>
            </div>
          </div>

          {/* Acoustic Signal Detail Card */}
          <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs space-y-4">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-slate-800 uppercase tracking-wider">
                Acoustic Signal & INMP441 Microphone
              </span>
              <span className="text-[10px] font-mono text-slate-400">I2S DMA • 16,000 Hz 16-bit</span>
            </div>

            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-4 rounded-xl bg-purple-50/50 border border-purple-100">
              <div className="space-y-1">
                <div className="flex items-baseline gap-2">
                  <span className="text-3xl font-bold font-mono text-purple-900">
                    {isAcousticNotDetected ? '0 Hz' : `${pitchHz} Hz`}
                  </span>
                  <span className="text-xs font-semibold text-purple-700">
                    {isAcousticNotDetected ? 'Status: Not Detected (0 Hz)' : `Status: Dominant Peak ${pitchHz} Hz`}
                  </span>
                </div>
                <p className="text-xs text-slate-600">
                  {latestClip 
                    ? `Latest 3.0s sample recorded at ${latestClip.recorded_time || 'recent cycle'} (${latestClip.trigger || 'cooldown cycle'})` 
                    : 'Awaiting next 5-minute cooldown audio buffer upload.'}
                </p>
              </div>

              {latestClip && (
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => handleTogglePlay(latestClip)}
                    className="flex items-center gap-1.5 px-4 py-2 bg-purple-700 hover:bg-purple-800 text-white rounded-lg text-xs font-semibold transition shadow-2xs"
                  >
                    {isPlaying && activePlayingId === latestClip.id ? (
                      <>
                        <Pause className="w-3.5 h-3.5" />
                        <span>Pause Audio</span>
                      </>
                    ) : (
                      <>
                        <Play className="w-3.5 h-3.5" />
                        <span>Play 3s Hive WAV</span>
                      </>
                    )}
                  </button>
                </div>
              )}
            </div>
          </div>

          {/* Wi-Fi & Power Diagnostics */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
            <div className="bg-white rounded-xl border border-slate-200/90 p-4 shadow-2xs">
              <span className="text-[11px] font-semibold text-slate-400 uppercase tracking-wide flex items-center gap-1.5">
                <Wifi className="w-3.5 h-3.5 text-slate-400" />
                <span>Network Connection</span>
              </span>
              <span className="text-sm font-bold text-slate-900 mt-1 block">Wi-Fi Connected (RSSI: -58 dBm)</span>
            </div>

            <div className="bg-white rounded-xl border border-slate-200/90 p-4 shadow-2xs">
              <span className="text-[11px] font-semibold text-slate-400 uppercase tracking-wide flex items-center gap-1.5">
                <Zap className="w-3.5 h-3.5 text-amber-500" />
                <span>Power Source</span>
              </span>
              <span className="text-sm font-bold text-slate-900 mt-1 block">{telemetry?.power_source || '5V USB / Grid Plugged In'}</span>
            </div>
          </div>
        </div>
      )}

      {/* ================= TAB 2: AI ANALYSIS ================= */}
      {activeTab === 2 && (
        <div className="space-y-5 animate-in fade-in duration-150">
          {/* Classification Banner */}
          <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs space-y-2">
            <span className="text-xs font-bold text-slate-800 uppercase tracking-wider block">
              Colony Condition Classification
            </span>
            <div className="flex items-center gap-2">
              <span className={`text-base font-bold px-3 py-1 rounded-md border ${currentColors.badge}`}>
                {conditionLabel}
              </span>
              <span className="text-xs font-mono text-slate-500">
                Confidence: <strong className="text-slate-800">{isAcousticNotDetected ? '0%' : `${confidence}%`}</strong>
              </span>
            </div>
            <p className="text-xs text-slate-600">
              Processed via Mel-Frequency Cepstral Coefficients (MFCC) feature extraction and Support Vector Classifier.
            </p>
          </div>

          {/* Explanation Card */}
          <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs space-y-2">
            <h4 className="text-xs font-bold text-slate-800 uppercase tracking-wider">
              Diagnostic Explanation
            </h4>
            <p className="text-xs text-slate-700 leading-relaxed">
              {isAcousticNotDetected 
                ? 'No Buzz Detected: The acoustic microphone recorded 0 Hz (silence). The AI cannot detect active worker humming, queen piping, or colony vibration until acoustic buzz signals are present.'
                : `The AI analyzed the hive's acoustic frequency (${pitchHz} Hz), temperature (${currentTemp.toFixed(1)}°C), and humidity (${currentHum.toFixed(1)}%). Dominant acoustic harmonic clustering falls within the expected ${conditionLabel} signature.`}
            </p>
          </div>

          {/* Detected Colony Conditions Matrix */}
          <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs space-y-3">
            <h4 className="text-xs font-bold text-slate-800 uppercase tracking-wider">
              Detected Colony Conditions
            </h4>
            <div className="divide-y divide-slate-100 text-xs">
              {[
                { name: 'Queen Present', detected: !isAnyNoBuzz && conditionLabel.toLowerCase().includes('present'), color: 'text-emerald-700' },
                { name: 'Queen Absent', detected: !isAnyNoBuzz && conditionLabel.toLowerCase().includes('absent'), color: 'text-red-700' },
                { name: 'Queen Accepted', detected: !isAnyNoBuzz && conditionLabel.toLowerCase().includes('accepted'), color: 'text-sky-700' },
                { name: 'Queen Rejected', detected: !isAnyNoBuzz && conditionLabel.toLowerCase().includes('rejected'), color: 'text-amber-700' },
                { name: 'Colony Acoustic Buzz', detected: !isAnyNoBuzz, color: isAnyNoBuzz ? 'text-red-700' : 'text-emerald-700', label: isAnyNoBuzz ? 'No Buzz Detected' : 'Buzzing Active' }
              ].map((item, idx) => (
                <div key={idx} className="py-2.5 flex items-center justify-between">
                  <span className="font-medium text-slate-700 flex items-center gap-2">
                    <span className={`w-2 h-2 rounded-full ${item.detected ? 'bg-emerald-500' : 'bg-slate-300'}`} />
                    {item.name}
                  </span>
                  <span className={`font-semibold ${item.detected ? item.color : 'text-slate-400'}`}>
                    {item.label || (item.detected ? 'Detected' : 'Not Detected')}
                  </span>
                </div>
              ))}
            </div>
          </div>

          {/* AI Recommendation Card */}
          <div className="p-4 rounded-xl bg-blue-50/80 border border-blue-200/90 space-y-1.5 shadow-2xs">
            <div className="text-blue-900 font-bold text-xs">
              <span>AI Recommendation</span>
            </div>
            <p className="text-xs text-blue-800 leading-relaxed">
              {conditionLabel.toLowerCase().includes('absent')
                ? 'Inspect frames for emergency queen cells or introduce a new mated queen promptly.'
                : conditionLabel.toLowerCase().includes('rejected')
                ? 'Check release cage immediately and examine worker agitation to prevent queen balling.'
                : conditionLabel.toLowerCase().includes('accepted')
                ? 'Queen accepted. Avoid disturbing brood box for 5 days while egg laying stabilizes.'
                : isAnyNoBuzz
                ? 'Verify microphone wiring on ESP32 node and inspect hive box activity.'
                : 'Continue routine monitoring. No intervention required.'}
            </p>
          </div>

          {/* Hardware Diagnostic Advisory */}
          {hasSensorNotDetected && (
            <div className="p-4 rounded-xl bg-amber-50/90 border border-amber-200/90 space-y-2 text-xs">
              <div className="text-amber-900 font-bold">
                <span>Sensor Connection & Diagnostic Advisory</span>
              </div>
              <ul className="list-disc list-inside space-y-1 text-amber-800">
                {isTempNotDetected && <li>DHT22 Temperature: Check DATA wire on GPIO 4 & verify 3.3V power/GND.</li>}
                {isHumNotDetected && <li>DHT22 Humidity: Verify clean sensor contacts on GPIO 4.</li>}
                {isAcousticNotDetected && <li>INMP441 Microphone: Check I2S pins: D33 (SD), D32 (SCK), D25 (WS), 3.3V (VDD), GND.</li>}
              </ul>
              <p className="text-[11px] text-amber-700 italic">
                After reconnecting wires, press the EN (Reset) button on the ESP32 node to refresh live AI diagnostics.
              </p>
            </div>
          )}
        </div>
      )}

      {/* ================= TAB 3: HISTORY (SWIPABLE CHARTS & ACOUSTIC FREQUENCY - ADMIN/OWNER ONLY) ================= */}
      {activeTab === 3 && isAdmin && (
        <div className="space-y-6 animate-in fade-in duration-150">
          {/* Timeframe selector */}
          <div className="flex items-center justify-between pb-2 border-b border-slate-200">
            <span className="text-xs font-bold text-slate-800 uppercase tracking-wider">
              Telemetry & Acoustic History
            </span>
            <div className="flex items-center gap-1 bg-slate-100 p-0.5 rounded-lg border border-slate-200 text-xs">
              {[
                { id: '24h', label: '24 Hours' },
                { id: '7d', label: '7 Days' },
                { id: '30d', label: '30 Days' }
              ].map((tf) => (
                <button
                  key={tf.id}
                  onClick={() => setTimeframe(tf.id)}
                  className={`px-3 py-1 rounded text-xs font-semibold transition cursor-pointer ${
                    timeframe === tf.id 
                      ? 'bg-white text-slate-900 shadow-2xs font-bold' 
                      : 'text-slate-500 hover:text-slate-800'
                  }`}
                  title={`Filter history to last ${tf.label}`}
                >
                  {tf.label}
                </button>
              ))}
            </div>
          </div>

          {/* 1. Temperature History (°C) (Swipable) */}
          <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-bold text-slate-900">Temperature History (°C)</h3>
              <span className="text-[11px] font-bold text-emerald-800 bg-emerald-50 border border-emerald-200 px-2 py-0.5 rounded">
                Avg: {avgStats.temp}°C
              </span>
            </div>

            <div className="flex items-center gap-2 text-[11px] text-slate-500 font-medium">
              <span className="w-2.5 h-2.5 rounded-full bg-emerald-500 shrink-0" />
              <span>Optimal Brood Nest Zone (32.0°C - 36.0°C • Alert ≤ 25.0°C / ≥ 85.0°C)</span>
            </div>

            {/* Swipable chart wrapper */}
            <SwipableChartContainer dataLength={syncedHistory.length} height={175}>
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={syncedHistory} margin={{ top: 10, right: 20, left: -20, bottom: 5 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                  <XAxis dataKey="displayDate" tick={{ fontSize: 10, fill: '#64748b' }} interval={0} />
                  <YAxis domain={[15, 55]} tick={{ fontSize: 10, fill: '#64748b' }} />
                  <Tooltip 
                    contentStyle={{ fontSize: 11, borderRadius: 8, borderColor: '#e2e8f0' }} 
                    labelFormatter={(label, payload) => payload?.[0]?.payload?.fullDate || label}
                  />
                  <ReferenceArea y1={32} y2={36} fill="#10b981" fillOpacity={0.12} />
                  <Area type="monotone" dataKey="temp" stroke="#f59e0b" fill="#f59e0b" fillOpacity={0.1} strokeWidth={2.2} dot={{ r: 3, fill: '#f59e0b' }} />
                </AreaChart>
              </ResponsiveContainer>
            </SwipableChartContainer>
          </div>

          {/* 2. Relative Humidity (%) (Swipable) */}
          <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-bold text-slate-900">Relative Humidity (%)</h3>
              <span className="text-[11px] font-bold text-sky-800 bg-sky-50 border border-sky-200 px-2 py-0.5 rounded">
                Avg: {avgStats.hum}%
              </span>
            </div>

            <div className="flex items-center gap-2 text-[11px] text-slate-500 font-medium">
              <span className="w-2.5 h-2.5 rounded-full bg-sky-500 shrink-0" />
              <span>Optimal Hive Humidity Zone (50% - 75% • Alert ≥ 85%)</span>
            </div>

            {/* Swipable chart wrapper */}
            <SwipableChartContainer dataLength={syncedHistory.length} height={175}>
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={syncedHistory} margin={{ top: 10, right: 20, left: -20, bottom: 5 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                  <XAxis dataKey="displayDate" tick={{ fontSize: 10, fill: '#64748b' }} interval={0} />
                  <YAxis domain={[30, 100]} tick={{ fontSize: 10, fill: '#64748b' }} />
                  <Tooltip 
                    contentStyle={{ fontSize: 11, borderRadius: 8, borderColor: '#e2e8f0' }} 
                    labelFormatter={(label, payload) => payload?.[0]?.payload?.fullDate || label}
                  />
                  <ReferenceArea y1={50} y2={75} fill="#0284c7" fillOpacity={0.12} />
                  <Area type="monotone" dataKey="humidity" stroke="#0284c7" fill="#0284c7" fillOpacity={0.1} strokeWidth={2.2} dot={{ r: 3, fill: '#0284c7' }} />
                </AreaChart>
              </ResponsiveContainer>
            </SwipableChartContainer>
          </div>

          {/* 3. Acoustic Frequency History (Hz) (Swipable) */}
          <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-bold text-slate-900">Acoustic Frequency History (Hz)</h3>
              <span className="text-[11px] font-bold text-purple-800 bg-purple-50 border border-purple-200 px-2 py-0.5 rounded">
                Avg: {avgStats.pitch} Hz
              </span>
            </div>

            <div className="flex items-center gap-2 text-[11px] text-slate-500 font-medium">
              <span className="w-2.5 h-2.5 rounded-full bg-emerald-500 shrink-0" />
              <span>Normal Queenright Hum Zone (35 - 260 Hz • &lt; 35 Hz No Buzz)</span>
            </div>

            {/* Swipable chart wrapper */}
            <SwipableChartContainer dataLength={syncedHistory.length} height={190}>
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={syncedHistory} margin={{ top: 10, right: 20, left: -20, bottom: 5 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                  <XAxis dataKey="displayDate" tick={{ fontSize: 10, fill: '#64748b' }} interval={0} />
                  <YAxis domain={[0, 360]} tick={{ fontSize: 10, fill: '#64748b' }} />
                  <Tooltip 
                    contentStyle={{ fontSize: 11, borderRadius: 8, borderColor: '#e2e8f0' }} 
                    labelFormatter={(label, payload) => payload?.[0]?.payload?.fullDate || label}
                  />
                  <ReferenceArea y1={35} y2={260} fill="#10b981" fillOpacity={0.12} />
                  <ReferenceLine y={35} stroke="#ef4444" strokeDasharray="2 2" />
                  <Area type="monotone" dataKey="pitch" stroke="#8b5cf6" fill="#8b5cf6" fillOpacity={0.15} strokeWidth={2.4} dot={{ r: 3, fill: '#8b5cf6' }} />
                </AreaChart>
              </ResponsiveContainer>
            </SwipableChartContainer>
          </div>

          {/* 4. AI Queen Condition Timeline */}
          {conditionTimeline.length > 0 && (
            <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs space-y-3">
              <h3 className="text-xs font-bold text-slate-800 uppercase tracking-wider">
                AI Queen Condition Timeline
              </h3>
              <div className="flex flex-wrap gap-2 pt-1">
                {conditionTimeline.map((item, idx) => {
                  const colors = getConditionColor(item.condition);
                  return (
                    <div key={idx} className="flex items-center gap-2 px-3 py-1.5 rounded-lg border border-slate-200 bg-slate-50/60 text-xs">
                      <span className="font-mono text-slate-500 text-[11px]">{item.date}</span>
                      <span className={`px-2 py-0.5 rounded font-semibold text-[10px] border ${colors.badge}`}>
                        {item.condition}
                      </span>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* 5. Recent Hive Audio Recordings (Last 5 with interactive audio playback) */}
          <div className="bg-white rounded-xl border border-slate-200/90 p-5 shadow-2xs space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-slate-100">
              <h3 className="text-sm font-bold text-slate-900">Recent Hive Buzz Audio Recordings</h3>
              <span className="text-[10px] font-mono text-slate-400">
                ESP32 16kHz DMA INMP441
              </span>
            </div>

            <p className="text-xs text-slate-500">
              Recent 3.0-second acoustic audio clips captured on boot and cycle cooldown. Click play to listen.
            </p>

            {audioClips.length === 0 ? (
              <div className="p-6 text-center text-xs text-slate-400 bg-slate-50 rounded-lg border border-slate-100">
                Awaiting buzz recordings from {hive.name}...
              </div>
            ) : (
              <div className="space-y-2.5">
                {audioClips.slice(0, 5).map((clip) => {
                  const isThisPlaying = isPlaying && activePlayingId === clip.id;
                  const hz = clip.frequency || 0;
                  const colors = getConditionColor(clip.condition || 'Queen Present');

                  return (
                    <div 
                      key={clip.id} 
                      className={`flex items-center justify-between p-3 rounded-lg border transition ${
                        isThisPlaying ? 'bg-purple-50/80 border-purple-300' : 'bg-slate-50/60 border-slate-200/80 hover:bg-slate-50'
                      }`}
                    >
                      <div className="flex items-center gap-3">
                        <button
                          type="button"
                          onClick={() => handleTogglePlay(clip)}
                          className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold transition shadow-2xs shrink-0 ${
                            isThisPlaying ? 'bg-slate-900 text-white' : 'bg-amber-400 hover:bg-amber-500 text-slate-950'
                          }`}
                          title={isThisPlaying ? 'Stop playback' : 'Play recording'}
                        >
                          {isThisPlaying ? (
                            <>
                              <Pause className="w-3 h-3" />
                              <span>Pause</span>
                            </>
                          ) : (
                            <>
                              <Play className="w-3 h-3" />
                              <span>Play</span>
                            </>
                          )}
                        </button>

                        <div>
                          <div className="flex items-center gap-2">
                            <span className="text-xs font-bold text-slate-900">
                              {clip.id.toUpperCase().replace('_', ' ')}
                            </span>
                            <span className="text-[11px] font-mono text-slate-500">
                              {clip.recorded_date ? `${clip.recorded_date}, ` : ''}{clip.timestamp || clip.recorded_time}
                            </span>
                          </div>
                          <span className="text-[10px] text-slate-400 block">
                            Trigger: <strong className="text-slate-600">{clip.trigger || 'Cooldown Cycle'}</strong>
                          </span>
                        </div>
                      </div>

                      <div className="flex items-center gap-2">
                        <span className="text-xs font-mono font-bold text-purple-700 bg-purple-100/60 px-2 py-0.5 rounded">
                          {hz} Hz
                        </span>
                        <span className={`text-[10px] font-semibold px-2 py-0.5 rounded border ${colors.badge}`}>
                          {clip.condition || 'Queen Present'}
                        </span>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
