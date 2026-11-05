import React from 'react';
import { ShieldCheck, Loader2 } from 'lucide-react';

export default function ScreenLoader({ message = 'Loading BeeWare Apiary Console...' }) {
  return (
    <div className="fixed inset-0 z-[9999] bg-slate-950 flex flex-col items-center justify-center p-4 selection:bg-amber-100 selection:text-amber-900 animate-fadeIn">
      {/* Decorative background glow */}
      <div className="absolute w-72 h-72 bg-amber-500/10 rounded-full blur-3xl pointer-events-none -top-10" />
      <div className="absolute w-64 h-64 bg-amber-600/5 rounded-full blur-2xl pointer-events-none -bottom-10" />

      <div className="relative flex flex-col items-center text-center space-y-5 max-w-xs">
        {/* Animated Brand Shield with Spinner Ring */}
        <div className="relative flex items-center justify-center">
          {/* Outer glowing pulsing border */}
          <div className="w-16 h-16 rounded-2xl bg-amber-400/10 border border-amber-400/30 flex items-center justify-center shadow-xl shadow-amber-400/5">
            <ShieldCheck className="w-8 h-8 text-amber-400 animate-pulse" />
          </div>
          {/* Rotating Spinner Ring */}
          <div className="absolute -inset-1.5 rounded-2xl border-2 border-transparent border-t-amber-400 border-r-amber-400/40 animate-spin" />
        </div>

        {/* Text Details */}
        <div className="space-y-1.5">
          <h2 className="text-base font-bold text-white tracking-tight">
            BeeWare Apiary Console
          </h2>
          <p className="text-xs text-slate-400 font-medium animate-pulse">
            {message}
          </p>
        </div>

        {/* Mini progress bar */}
        <div className="w-40 h-1 bg-slate-800 rounded-full overflow-hidden">
          <div className="w-full h-full bg-amber-400 rounded-full animate-pulse" />
        </div>
      </div>
    </div>
  );
}
