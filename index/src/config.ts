import type { Locale } from './i18n/messages';

/** Product links and copy — edit when URLs change. */
export const site = {
  name: 'Nerve',
  /** Primary hero line (split for display). */
  headline: ['Every job.', 'One glance.'],
  subhead: 'Running, waiting, or broken—right in the menu bar.',
  github: 'https://github.com/Roy-Kid/nerve',
  /** Replace with the live App Store product URL when published. */
  appStore: 'https://apps.apple.com/app/nerve',
  appStoreReady: false,
  /** In-site documentation hub (subpages under /docs). */
  docs: '/docs',
  pluginDocs: '/docs/plugin',
  macos: '/macos',
  tmuxGuideZh: '/tmux/zh',
  tmuxGuideEn: '/tmux/en',
  requirements: {
    macos: 'macOS 14+',
    xcode: 'Xcode 15+',
  },
} as const;

export function getTmuxGuidePath(locale: Locale) {
  return locale === 'zh' ? site.tmuxGuideZh : site.tmuxGuideEn;
}

export const jobs = [
  { id: 'claude', label: 'Claude Code', status: 'running' as const, alias: 'studio' },
  { id: 'build', label: 'xcodebuild Nerve', status: 'attention' as const, alias: 'studio' },
  { id: 'codex', label: 'Codex · refactor', status: 'waiting' as const, alias: 'gpu-box' },
  { id: 'tests', label: 'pytest suite', status: 'running' as const, alias: 'ci' },
  { id: 'fail', label: 'deploy edge', status: 'problem' as const, alias: 'edge' },
] as const;

export type JobStatus = (typeof jobs)[number]['status'];
export type StatusTone = JobStatus | 'inactive' | 'success';

export const statusMeta: Record<
  StatusTone,
  { label: string; color: string; hint: string }
> = {
  problem: { label: 'Problem', color: '#ff453a', hint: 'Failed / blocked' },
  attention: { label: 'Attention', color: '#ff9f0a', hint: 'Needs you' },
  waiting: { label: 'Waiting', color: '#bf5af2', hint: 'System / deps' },
  running: { label: 'Running', color: '#0a84ff', hint: 'In flight' },
  success: { label: 'Success', color: '#30d158', hint: 'Monitor wait / done' },
  inactive: { label: 'Inactive', color: '#8e8e93', hint: 'Ready / unknown' },
};

export const truths = [
  {
    title: 'One live ribbon.',
    body: 'See every job at a glance.',
  },
  {
    title: 'Only when it matters.',
    body: 'Running, waiting, and failed stay distinct.',
  },
  {
    title: 'Open and local.',
    body: 'The protocol and source are yours to inspect.',
  },
] as const;

export const sources = [
  { name: 'Claude Code', how: 'Marketplace plugin · fail-open hooks' },
  { name: 'Codex', how: 'Same marketplace · codex plugin add' },
  { name: 'Grok', how: 'Claude-compatible hooks' },
  { name: 'Anything HTTP', how: 'POST the open snapshot contract' },
] as const;

/** Main-session lifecycle as the ribbon / panel see it (one job per conversation). */
export const lifecycle = [
  {
    phase: 'Start',
    facet: 'starting',
    ribbon: 'inactive' as const,
    note: 'Session opens — Ready. Running only after the first prompt.',
  },
  {
    phase: 'Work',
    facet: 'thinking · tool',
    ribbon: 'running' as const,
    note: 'Main-thread prompts and tools. Subagents only refine the same row.',
  },
  {
    phase: 'Waiting on you',
    facet: 'idle · permission',
    ribbon: 'attention' as const,
    note: 'Empty background queue + input needed, or an approval prompt.',
  },
  {
    phase: 'Background',
    facet: 'subagent · shell',
    ribbon: 'running' as const,
    note: 'Shell / subagent still running — Running, never Attention.',
  },
  {
    phase: 'Monitor',
    facet: 'monitor',
    ribbon: 'success' as const,
    note: 'Monitor open: phase done, waiting for stream feedback (green).',
  },
  {
    phase: 'End',
    facet: 'ended',
    ribbon: 'inactive' as const,
    note: 'SessionEnd removes the job immediately.',
  },
] as const;

export const designNotes = [
  {
    title: 'Jobs, not agents',
    body: 'A job is one unit of work with a producer — Claude, Codex, a build, anything that can POST — while machines stay in Settings as tunnels you configure.',
  },
  {
    title: 'Memory-only runtime',
    body: 'Jobs, timelines, and pending actions never touch disk, so only preferences and a managed ~/.ssh/config block survive a quit.',
  },
  {
    title: 'Fail-open hooks',
    body: 'Agent plugins never block on Nerve, and there are no project env vars because ingest is always loopback :17890.',
  },
  {
    title: 'Out of scope on purpose',
    body: 'Nerve will never reverse-control an agent, sync to a cloud, or keep history on disk, and Open/Focus only jumps you back to the agent UI.',
  },
] as const;
