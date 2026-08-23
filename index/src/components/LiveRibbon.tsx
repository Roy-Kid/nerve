import { jobs, statusMeta } from '../config';
import type { StatusRibbonSegment } from '../lib/statusRibbon';
import { StatusRibbonBand } from './StatusRibbonBand';
import { useLocale } from '../i18n/locale';
import { cn } from '../lib/utils';

type LiveRibbonProps = {
  /** Visual weight of the bar */
  size?: 'sm' | 'md' | 'lg';
  /** Whether the macOS-style shimmer and status pulses run */
  alive?: boolean;
  /** Show job labels under segments */
  showLabels?: boolean;
  /** Optional external “load” 0–1 that stretches the bar */
  load?: number;
  /** Which half of the page this sits on — decides the label colours. */
  tone?: 'paper' | 'night';
  /** Height / glow the surrounding section wants on the bar itself. */
  trackClassName?: string;
  className?: string;
};

const trackHeight = {
  sm: 'h-[7px]',
  md: 'h-3',
  lg: 'h-[15px]',
} as const;

const track =
  'flex w-full origin-left overflow-hidden rounded-full bg-[rgb(82_100_131/8%)] ' +
  'shadow-[inset_0_0_0_1px_rgb(62_82_118/6%),0_7px_22px_rgb(58_79_117/10%)] ' +
  'transition-transform duration-800 ease-page motion-reduce:transition-none';

export function LiveRibbon({
  size = 'md',
  alive = true,
  showLabels = false,
  load = 1,
  tone = 'paper',
  trackClassName,
  className = '',
}: LiveRibbonProps) {
  const { t } = useLocale();
  const night = tone === 'night';
  const segments: StatusRibbonSegment[] = jobs.map((job) => ({
    id: job.id,
    status: job.status,
    weight: 1,
    title: `${job.label} · ${t.preview.status[job.status]}`,
  }));

  const scaleX = 0.55 + 0.45 * Math.min(1, Math.max(0.15, load));

  return (
    <div className={cn('w-full', className)}>
      <StatusRibbonBand
        segments={segments}
        animated={alive}
        className={cn(track, trackHeight[size], trackClassName)}
        style={{ transform: `scaleX(${scaleX})` }}
      />
      {showLabels && (
        <ul
          className={cn(
            'm-0 flex list-none flex-col p-0',
            night ? 'mt-[22px] gap-2.5' : 'mt-[0.9rem] gap-[0.38rem]',
          )}
        >
          {jobs.map((job) => (
            <li
              key={job.id}
              className={cn(
                'grid items-center gap-[0.52rem] text-[0.75rem]',
                night ? 'grid-cols-[8px_minmax(0,1fr)_auto]' : 'grid-cols-[8px_1fr_auto]',
              )}
            >
              <i
                className="size-2 rounded-full shadow-[0_2px_7px_rgb(49_66_99/12%)]"
                style={{ background: statusMeta[job.status].color }}
              />
              <span
                className={cn(
                  'overflow-hidden font-[550] text-ellipsis whitespace-nowrap',
                  night ? 'text-night-text' : 'text-[#354157]',
                )}
              >
                {job.label}
              </span>
              <span
                className={cn(
                  'font-mono text-[0.64rem] whitespace-nowrap',
                  night
                    ? 'text-label-3 max-sm:hidden'
                    : 'text-ink-faint max-sm:max-w-[8.5rem] max-sm:overflow-hidden max-sm:text-ellipsis',
                )}
              >
                {job.alias} · {t.preview.status[job.status]}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
