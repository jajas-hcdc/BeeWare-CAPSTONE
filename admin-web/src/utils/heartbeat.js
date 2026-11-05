/**
 * BeeWare Hardware Watchdog Utility
 * Monitors ESP32 telemetry timestamp to determine real-time connectivity status.
 */

export function getNodeWatchdogStatus(telemetry, fallbackTimeString) {
  let timestampMs = null;

  if (telemetry?.epoch) {
    timestampMs = telemetry.epoch > 1e11 ? telemetry.epoch : telemetry.epoch * 1000;
  } else if (telemetry?.updatedAt?.toMillis) {
    timestampMs = telemetry.updatedAt.toMillis();
  } else if (telemetry?.timestamp) {
    const parsed = Date.parse(telemetry.timestamp);
    if (!isNaN(parsed)) {
      timestampMs = parsed;
    }
  }

  if (!timestampMs && fallbackTimeString) {
    const parsed = Date.parse(fallbackTimeString);
    if (!isNaN(parsed)) timestampMs = parsed;
  }

  if (timestampMs) {
    const elapsedMinutes = (Date.now() - timestampMs) / (1000 * 60);

    if (elapsedMinutes < 5) {
      return {
        status: 'online',
        label: 'Online',
        badgeClass: 'text-emerald-800 bg-emerald-50 border-emerald-200',
        dotClass: 'bg-emerald-500 animate-pulse',
        elapsedDesc: 'Active now (< 5m)',
        color: 'emerald'
      };
    } else if (elapsedMinutes <= 15) {
      return {
        status: 'stale',
        label: 'Delayed (Stale)',
        badgeClass: 'text-amber-800 bg-amber-50 border-amber-200',
        dotClass: 'bg-amber-500',
        elapsedDesc: `${Math.round(elapsedMinutes)}m since ping`,
        color: 'amber'
      };
    } else {
      const hours = Math.round(elapsedMinutes / 60);
      return {
        status: 'offline',
        label: 'Offline',
        badgeClass: 'text-red-800 bg-red-50 border-red-200',
        dotClass: 'bg-red-500',
        elapsedDesc: hours > 0 ? `${hours}h since ping` : `${Math.round(elapsedMinutes)}m ago`,
        color: 'red'
      };
    }
  }

  // Active default for local testing / live simulation
  return {
    status: 'online',
    label: 'Online',
    badgeClass: 'text-emerald-800 bg-emerald-50 border-emerald-200',
    dotClass: 'bg-emerald-500 animate-pulse',
    elapsedDesc: 'Live gateway sync',
    color: 'emerald'
  };
}
