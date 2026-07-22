/** Product links and copy — edit when URLs change. */
export const site = {
  name: 'Nerve',
  /** Primary hero line (split for display). */
  headline: ['The pulse', 'behind your work'],
  subhead:
    'A quiet macOS menu-bar ribbon for agents, builds, tests, and long jobs. Nerve never runs them — it listens while they work.',
  github: 'https://github.com/Roy-Kid/nerve',
  /** Replace with the live App Store product URL when published. */
  appStore: 'https://apps.apple.com/app/nerve',
  appStoreReady: false,
  docs: 'https://github.com/Roy-Kid/nerve#readme',
  pluginDocs: 'https://github.com/Roy-Kid/nerve/tree/main/plugins/nerve',
  requirements: {
    macos: 'macOS 14+',
    xcode: 'Xcode 15+',
  },
} as const;

export const jobs = [
  { id: 'claude', label: 'Claude Code', status: 'running' as const, alias: 'studio' },
  { id: 'build', label: 'xcodebuild Nerve', status: 'attention' as const, alias: 'studio' },
  { id: 'codex', label: 'Codex · refactor', status: 'waiting' as const, alias: 'gpu-box' },
  { id: 'tests', label: 'pytest suite', status: 'running' as const, alias: 'ci' },
  { id: 'fail', label: 'deploy edge', status: 'problem' as const, alias: 'edge' },
] as const;

export type JobStatus = (typeof jobs)[number]['status'];

export const statusMeta: Record<
  JobStatus | 'inactive' | 'success',
  { label: string; color: string; hint: string }
> = {
  problem: { label: 'Problem', color: '#ff3b30', hint: 'Failed / blocked' },
  attention: { label: 'Attention', color: '#ff9500', hint: 'Needs you' },
  waiting: { label: 'Waiting', color: '#af52de', hint: 'System / deps' },
  running: { label: 'Running', color: '#007aff', hint: 'In flight' },
  success: { label: 'Success', color: '#34c759', hint: 'Done (sessions leave)' },
  inactive: { label: 'Inactive', color: '#8e8e93', hint: 'Idle / unknown' },
};

export const truths = [
  {
    kicker: 'Listen, don’t drive',
    title: 'Nerve is not another agent runner.',
    body: 'Your harnesses keep doing the work. Nerve only aggregates the status they push — into one continuous ribbon in the menu bar.',
  },
  {
    kicker: 'Color is the signal',
    title: 'Length for load. Hue for urgency.',
    body: 'The ribbon stretches with active jobs. Blue runs, amber asks, red stops you. Glance once — no Dock icon, no floating window tax.',
  },
  {
    kicker: 'Local by default',
    title: 'Memory-only runtime. Loopback only.',
    body: 'Jobs and timelines die with the process. Preferences stay on this Mac. Ingest is 127.0.0.1 — remotes arrive only through SSH tunnels you own.',
  },
] as const;

export const sources = [
  { name: 'Claude Code', how: 'Marketplace plugin · fail-open hooks' },
  { name: 'Codex', how: 'Same marketplace · codex plugin add' },
  { name: 'Grok', how: 'Claude-compatible hooks' },
  { name: 'Anything HTTP', how: 'POST snapshots to :17890' },
] as const;

/** Main-session lifecycle as the ribbon / panel see it (one job per conversation). */
export const lifecycle = [
  {
    phase: 'Start',
    facet: 'starting',
    ribbon: 'running' as const,
    note: 'Session opens. One job id per conversation.',
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
    facet: 'subagent',
    ribbon: 'running' as const,
    note: 'Still working — background tasks or SubagentStart, not human idle.',
  },
  {
    phase: 'End',
    facet: 'ended',
    ribbon: 'inactive' as const,
    note: 'SessionEnd removes the job immediately. No Success linger.',
  },
] as const;

export const designNotes = [
  {
    title: 'Jobs, not agents',
    body: 'Machines live in Settings (tunnels). Work units are jobs with a producer — Claude, Codex, a build, anything that can POST.',
  },
  {
    title: 'Memory-only runtime',
    body: 'Jobs, timelines, and pending actions stay in RAM. Preferences use UserDefaults; SSH remotes live in a managed ~/.ssh/config block.',
  },
  {
    title: 'Fail-open hooks',
    body: 'Agent plugins never block on Nerve. No project env vars — ingest is always loopback :17890.',
  },
  {
    title: 'Out of scope (on purpose)',
    body: 'No multi-display ribbons, cloud sync, disk history, or in-app agent chat. Remotes poll their own action queues.',
  },
] as const;
