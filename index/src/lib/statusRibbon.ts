import { statusMeta, type StatusTone } from '../config';

export type StatusRibbonSegment = {
  id: string;
  status: StatusTone;
  weight: number;
  title?: string;
};

const MAX_BLEND = 0.045;
const NEIGHBOR_BLEND = 0.28;

function percent(value: number) {
  return `${Number((value * 100).toFixed(3))}%`;
}

/**
 * Match the macOS ribbon renderer: preserve a pure-color plateau for each
 * status, then use a short, weight-aware ramp across each boundary.
 */
export function buildStatusRibbonGradient(segments: readonly StatusRibbonSegment[]) {
  const visible = segments.filter((segment) => segment.weight > 0);
  const total = visible.reduce((sum, segment) => sum + segment.weight, 0);

  if (visible.length === 0 || total <= 0) {
    const idle = statusMeta.inactive.color;
    return `linear-gradient(90deg, ${idle} 0%, ${idle} 100%)`;
  }

  const normalized = visible.map((segment) => ({
    ...segment,
    weight: segment.weight / total,
  }));
  const stops: string[] = [];
  let cursor = 0;

  normalized.forEach((segment, index) => {
    const color = statusMeta[segment.status].color;
    const end = Math.min(1, cursor + segment.weight);

    if (index === 0) stops.push(`${color} 0%`);

    const next = normalized[index + 1];
    if (next) {
      const nextColor = statusMeta[next.status].color;
      const blend = Math.min(MAX_BLEND, Math.min(segment.weight, next.weight) * NEIGHBOR_BLEND);
      stops.push(`${color} ${percent(Math.max(cursor, end - blend))}`);
      stops.push(`${nextColor} ${percent(Math.min(1, end + blend))}`);
    } else {
      stops.push(`${color} 100%`);
    }

    cursor = end;
  });

  return `linear-gradient(90deg, ${stops.join(', ')})`;
}
