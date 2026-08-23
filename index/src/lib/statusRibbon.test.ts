import { describe, expect, it } from '@rstest/core';
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
      { id: 'waiting', status: 'waiting', weight: 1 },
    ]);

    expect(gradient).toContain('#ff453a 87.2%');
    expect(gradient).toContain('#bf5af2 92.8%');
  });

  it('falls back to the inactive color when no segment is visible', () => {
    expect(buildStatusRibbonGradient([])).toBe(
      'linear-gradient(90deg, #8e8e93 0%, #8e8e93 100%)',
    );
  });
});
