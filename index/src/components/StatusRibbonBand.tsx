import type { CSSProperties } from 'react';
import { cn } from '../lib/utils';
import {
  buildStatusRibbonGradient,
  type StatusRibbonSegment,
} from '../lib/statusRibbon';

type StatusRibbonBandProps = {
  segments: readonly StatusRibbonSegment[];
  animated?: boolean;
  className?: string;
  style?: CSSProperties;
};

/** Shared web rendering of the continuous status band used by the macOS GUI.
 *
 * The `status-ribbon-*` classes are the one hook the stylesheet still needs:
 * the shimmer and the per-status pulse are `::before` / `::after` animations,
 * which no utility can express.
 */
export function StatusRibbonBand({
  segments,
  animated = true,
  className,
  style,
}: StatusRibbonBandProps) {
  return (
    <div
      className={cn(
        'status-ribbon-band relative flex isolate overflow-hidden bg-no-repeat',
        animated && 'is-animated',
        className,
      )}
      style={{ ...style, backgroundImage: buildStatusRibbonGradient(segments) }}
    >
      {segments.map((segment) => (
        <span
          key={segment.id}
          className={cn(
            'status-ribbon-segment relative z-1 min-w-0 basis-0',
            `status-ribbon-segment--${segment.status}`,
          )}
          style={{ flexGrow: segment.weight }}
          title={segment.title}
        />
      ))}
    </div>
  );
}
