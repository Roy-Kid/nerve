import { useEffect, useMemo, useState } from 'react';
import { jobs, statusMeta, type JobStatus } from '../config';
import { usePrefersReducedMotion } from '../hooks/usePrefersReducedMotion';

type LiveRibbonProps = {
  /** Visual weight of the bar */
  size?: 'sm' | 'md' | 'lg';
  /** Whether segments gently breathe / shift */
  alive?: boolean;
  /** Show job labels under segments */
  showLabels?: boolean;
  /** Optional external “load” 0–1 that stretches the bar */
  load?: number;
  className?: string;
};

const WEIGHT: Record<JobStatus, number> = {
  running: 1.35,
  attention: 1.05,
  waiting: 0.9,
  problem: 0.75,
};

export function LiveRibbon({
  size = 'md',
  alive = true,
  showLabels = false,
  load = 1,
  className = '',
}: LiveRibbonProps) {
  const reduced = usePrefersReducedMotion();
  const [tick, setTick] = useState(0);

  useEffect(() => {
    if (!alive || reduced) return;
    const id = window.setInterval(() => setTick((t) => t + 1), 1800);
    return () => window.clearInterval(id);
  }, [alive, reduced]);

  const segments = useMemo(() => {
    return jobs.map((job, i) => {
      const base = WEIGHT[job.status];
      const wobble =
        alive && !reduced ? 1 + 0.08 * Math.sin(tick * 0.9 + i * 1.3) : 1;
      return {
        ...job,
        flex: base * wobble,
        color: statusMeta[job.status].color,
      };
    });
  }, [tick, alive, reduced]);

  const scaleX = 0.55 + 0.45 * Math.min(1, Math.max(0.15, load));

  return (
    <div className={`live-ribbon live-ribbon--${size} ${className}`.trim()}>
      <div className="live-ribbon-track" style={{ transform: `scaleX(${scaleX})` }}>
        {segments.map((seg) => (
          <div
            key={seg.id}
            className={`live-ribbon-seg live-ribbon-seg--${seg.status}`}
            style={{ flex: seg.flex, background: seg.color }}
            title={`${seg.label} · ${statusMeta[seg.status].label}`}
          >
            <span className="live-ribbon-sheen" aria-hidden="true" />
          </div>
        ))}
      </div>
      {showLabels && (
        <ul className="live-ribbon-labels">
          {segments.map((seg) => (
            <li key={seg.id}>
              <i style={{ background: seg.color }} />
              <span className="live-ribbon-label-name">{seg.label}</span>
              <span className="live-ribbon-label-meta">
                {seg.alias} · {statusMeta[seg.status].label}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
