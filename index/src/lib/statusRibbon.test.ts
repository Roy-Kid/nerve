import { describe, expect, it } from '@rstest/core';
import { jobs, statusMeta } from '../config';
import { buildStatusRibbonGradient } from './statusRibbon';

describe('status ribbon gradient', () => {
  it('uses the same capped transition width as the macOS renderer', () => {
    const gradient = buildStatusRibbonGradient([
      { id: 'running', status: 'running', weight: 1 },
      { id: 'attention', status: 'attention', weight: 1 },
    ]);

    expect(gradient).toBe(
      'linear-gradient(90deg, #0a84ff 0%, #0a84ff 45.5%, #ff9f0a 54.5%, #ff9f0a 100%)',
    );
  });

  it('keeps narrow segments readable with a weight-aware ramp', () => {
    const gradient = buildStatusRibbonGradient([
      { id: 'problem', status: 'problem', weight: 9 },
      { id: 'attention', status: 'attention', weight: 1 },
    ]);

    expect(gradient).toContain('#ff3b30 87.2%');
    expect(gradient).toContain('#ff9f0a 92.8%');
  });

  it('falls back to the inactive color when no segment is visible', () => {
    expect(buildStatusRibbonGradient([])).toBe(
      'linear-gradient(90deg, #8e8e93 0%, #8e8e93 100%)',
    );
  });

  it('paints the demo jobs in the shared palette order', () => {
    const gradient = buildStatusRibbonGradient(
      jobs.map((job) => ({ id: job.id, status: job.status, weight: 1 })),
    );

    for (const tone of Object.values(statusMeta)) {
      expect(gradient).toContain(tone.color);
    }
  });
});
