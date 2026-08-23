import { describe, expect, it } from '@rstest/core';
import { designNotes, jobs, lifecycle, site, sources, statusMeta, truths } from './config';

describe('site config', () => {
  it('exposes product name and GitHub URL', () => {
    expect(site.name).toBe('Nerve');
    expect(site.github).toMatch(/^https:\/\/github\.com\//);
  });

  it('exposes an App Store URL', () => {
    expect(site.appStore).toMatch(/^https:\/\/apps\.apple\.com\//);
  });

  it('has a two-line headline', () => {
    expect(site.headline).toHaveLength(2);
  });

  it('defines demo jobs for the live ribbon', () => {
    expect(jobs.length).toBeGreaterThanOrEqual(4);
  });

  it('covers the status palette', () => {
    expect(statusMeta.running.label).toBe('Running');
    expect(statusMeta.problem.color).toMatch(/^#/);
  });

  it('lists product truths and sources', () => {
    expect(truths).toHaveLength(3);
    expect(sources.length).toBeGreaterThanOrEqual(3);
  });

  it('defines main-session lifecycle for the Signal section', () => {
    expect(lifecycle.length).toBeGreaterThanOrEqual(4);
    expect(designNotes.length).toBeGreaterThanOrEqual(3);
    expect(lifecycle.some((s) => s.phase === 'End')).toBe(true);
  });

  it('points docs links at in-site subpages', () => {
    expect(site.docs).toBe('/docs');
    expect(site.pluginDocs).toBe('/docs/plugin');
    expect(site.macos).toBe('/macos');
    expect(site.tmuxGuideZh).toBe('/tmux/zh');
    expect(site.tmuxGuideEn).toBe('/tmux/en');
  });
});
