/**
 * BeeWare Colony Condition Classifier & Badge Formatter
 * Unifies queen condition classification and badge color styling across the console.
 * 
 * Rules:
 * - RED for: 'Queen Absent', 'No Buzz Detected' (or freq <= 0 / < 35 Hz / acoustic not detected)
 * - AMBER for: 'Queen Rejected'
 * - SKY BLUE for: 'Queen Accepted'
 * - EMERALD GREEN for: 'Queen Present'
 */

export function getConditionInfo(condition, freq) {
  let fNum = null;
  if (typeof freq === 'number') {
    fNum = freq;
  } else if (freq !== undefined && freq !== null) {
    const clean = freq.toString().replace(/[^0-9]/g, '');
    if (clean.length > 0) {
      const parsed = parseInt(clean, 10);
      if (!isNaN(parsed)) fNum = parsed;
    }
  }

  const raw = (condition || '').trim();
  const c = raw.toLowerCase();

  // 1. Check for silence / low frequency (< 35 Hz) / microphone not detected
  const isFreqSilent = fNum !== null && (fNum <= 0 || fNum < 35);
  const isAcousticNotDetected = c.includes('no buzz') || 
                                c.includes('not detected') || 
                                (typeof freq === 'string' && freq.toLowerCase().includes('not detected'));

  if (isFreqSilent || isAcousticNotDetected) {
    return {
      label: 'No Buzz Detected',
      badgeClass: 'text-red-700 bg-red-50 border border-red-200',
      dotClass: 'bg-red-500',
      stroke: '#ef4444',
      isAlert: true,
      status: 'critical'
    };
  }

  // 2. Queen Absent (RED)
  if (c.includes('absent')) {
    return {
      label: raw || 'Queen Absent',
      badgeClass: 'text-red-700 bg-red-50 border border-red-200',
      dotClass: 'bg-red-500',
      stroke: '#ef4444',
      isAlert: true,
      status: 'critical'
    };
  }

  // 3. Queen Rejected (AMBER)
  if (c.includes('rejected')) {
    return {
      label: raw || 'Queen Rejected',
      badgeClass: 'text-amber-800 bg-amber-50 border border-amber-200',
      dotClass: 'bg-amber-500',
      stroke: '#f59e0b',
      isAlert: true,
      status: 'warning'
    };
  }

  // 4. Queen Accepted (SKY)
  if (c.includes('accepted')) {
    return {
      label: raw || 'Queen Accepted',
      badgeClass: 'text-sky-700 bg-sky-50 border border-sky-200',
      dotClass: 'bg-sky-500',
      stroke: '#0284c7',
      isAlert: false,
      status: 'info'
    };
  }

  // 5. Queen Present (GREEN)
  return {
    label: raw || 'Queen Present',
    badgeClass: 'text-emerald-800 bg-emerald-50 border border-emerald-200',
    dotClass: 'bg-emerald-500',
    stroke: '#10b981',
    isAlert: false,
    status: 'nominal'
  };
}
