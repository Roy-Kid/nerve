/** Structured docs content for website subpages (source of truth; repo READMEs point here). */

export type DocNavItem = {
  slug: string;
  title: string;
  summary: string;
};

export const docNav: DocNavItem[] = [
  {
    slug: 'get-started',
    title: 'Get started',
    summary: 'Run Nerve, use the ribbon, verify with demo jobs.',
  },
  {
    slug: 'plugin',
    title: 'Agent plugins',
    summary: 'Claude Code, Codex, Grok marketplace hooks → local ingest.',
  },
  {
    slug: 'machines',
    title: 'Machines & remotes',
    summary: 'SSH reverse tunnels so remote agents report to this Mac.',
  },
  {
    slug: 'status',
    title: 'Status & lifecycle',
    summary: 'One job per session, facets, ribbon colors, design scope.',
  },
  {
    slug: 'ingest',
    title: 'Ingest API',
    summary: 'Loopback HTTP for snapshots, events, the surface stream, and actions.',
  },
  {
    slug: 'privacy',
    title: 'Privacy',
    summary: 'Memory-only runtime, loopback only, fail-open hooks.',
  },
];

export type DocBlock =
  | { type: 'p'; text: string }
  | { type: 'ul'; items: string[] }
  | { type: 'ol'; items: string[] }
  | { type: 'code'; lang?: string; code: string }
  | { type: 'table'; headers: string[]; rows: string[][] }
  | { type: 'callout'; title?: string; text: string }
  | { type: 'h2'; text: string }
  | { type: 'h3'; text: string };

export type DocPage = {
  slug: string;
  title: string;
  lede: string;
  blocks: DocBlock[];
};

export const docPages: DocPage[] = [
  {
    slug: 'get-started',
    title: 'Get started',
    lede: 'Nerve is a macOS menu-bar status hub. It does not run agents — it listens while they work.',
    blocks: [
      { type: 'h2', text: 'Requirements' },
      {
        type: 'ul',
        items: [
          'macOS 14+',
          'Xcode 15+ (to build the app from source)',
          'Python 3 (agent hook plugin only)',
          'OpenSSH client (for remote machines)',
        ],
      },
      { type: 'h2', text: 'Run from the repo' },
      {
        type: 'code',
        lang: 'bash',
        code: `./scripts/run.sh

# optional smoke checks
./scripts/inject_demo.sh
./scripts/verify_loop.sh`,
      },
      {
        type: 'p',
        text: 'A continuous ribbon appears in the macOS menu bar — no Dock icon, no floating window.',
      },
      { type: 'h2', text: 'Ribbon gestures' },
      {
        type: 'table',
        headers: ['Gesture', 'Action'],
        rows: [
          ['Left-click', 'Status panel (↑/↓, Enter expand; detail + timeline + actions)'],
          ['Right-click', 'Settings… or Quit Nerve'],
        ],
      },
      {
        type: 'p',
        text: 'Settings: General (menu bar, panel, endpoint) · Machines (SSH tunnels) · Appearance (ribbon size & colors) · Notifications · About.',
      },
      { type: 'h2', text: 'Website (this site)' },
      {
        type: 'code',
        lang: 'bash',
        code: `cd index-page
npm install
npm run dev      # local preview
npm run build    # static → index-page/dist/`,
      },
    ],
  },
  {
    slug: 'plugin',
    title: 'Agent plugins',
    lede: 'One marketplace plugin reports session lifecycle to Nerve as jobs. Fail-open, stateless, no project environment variables.',
    blocks: [
      {
        type: 'callout',
        title: 'One job per conversation',
        text: 'Job id is {producer}:{session_id} (never append agent_id). Subagents are not separate panel rows — they only refine the main session’s current facet. Tool noise inside subagents (agent_id set) is ignored. The app also drops legacy child rows (parentJobId / role=subagent / multi-segment ids). Stop waits for input; SessionEnd removes the row. If the host skips SessionEnd on /new · /clear · fork, the next SessionStart for the same UI slot posts an ended snapshot for the previous session_id. Local snapshots carry pid so a closed terminal can be reaped automatically.',
      },
      { type: 'h2', text: 'Install' },
      {
        type: 'table',
        headers: ['Harness', 'Install', 'Producer id'],
        rows: [
          [
            'Claude Code',
            '/plugin marketplace add Roy-Kid/nerve → /plugin install nerve@nerve',
            'claude-code',
          ],
          [
            'Codex',
            'codex plugin marketplace add Roy-Kid/nerve → codex plugin add nerve@nerve',
            'codex',
          ],
          ['Grok', 'Same Claude-compatible marketplace / plugin', 'grok'],
        ],
      },
      { type: 'h3', text: 'Claude Code' },
      {
        type: 'code',
        lang: 'text',
        code: `/plugin marketplace add Roy-Kid/nerve
/plugin install nerve@nerve`,
      },
      { type: 'h3', text: 'Codex CLI' },
      {
        type: 'code',
        lang: 'bash',
        code: `codex plugin marketplace add Roy-Kid/nerve
codex plugin add nerve@nerve

# local development
codex plugin marketplace add /ABS/PATH/TO/nerve
codex plugin add nerve@nerve`,
      },
      {
        type: 'p',
        text: 'Interactive Codex: /plugins → nerve → install. Trust hooks with /hooks if prompted.',
      },
      { type: 'h2', text: 'What hooks report' },
      {
        type: 'table',
        headers: ['Hook', 'Main session facets', 'Ribbon'],
        rows: [
          ['SessionStart', 'active + starting (“Ready”)', 'Inactive'],
          ['UserPromptSubmit', 'active + thinking', 'Running'],
          ['PreToolUse / PostToolUse (main thread)', 'active + tool / subagent', 'Running'],
          ['SubagentStart', 'active + current.type=subagent', 'Running'],
          ['SubagentStop (no other bg work)', 'active + thinking', 'Running'],
          ['Stop + shell/subagent bg tasks', 'current.type=subagent', 'Running'],
          ['Stop + monitor-only bg tasks', 'current.type=monitor + outcome=partial', 'Success'],
          ['Stop empty bg / idle_prompt', 'attention.reason=input', 'Attention'],
          ['idle_prompt + shell/agent toast', 'current.type=subagent', 'Running'],
          ['idle_prompt + monitor toast', 'current.type=monitor + partial', 'Success'],
          ['PermissionRequest / permission_prompt', 'attention.reason=approval', 'Attention'],
          ['SessionEnd', 'ended + endReason (+ success|cancelled)', 'Leaves panel'],
          ['SessionStart (new id, same UI slot)', 'previous id → ended (superseded)', 'Old row leaves'],
          ['Other Notification (no type)', 'active + info', 'Running'],
        ],
      },
      {
        type: 'ul',
        items: [
          'Fail-open: if Nerve is down, hooks exit 0 and never block the agent.',
          'No environment variables. Ingest URL is fixed: http://127.0.0.1:17890.',
          'Mostly stateless: each event posts a full job snapshot. A tiny temp-dir slot map remembers the last session_id per UI/process so /new without SessionEnd still closes the previous row.',
          'Snapshots include extensions.slot + extensions.pid (when known) so the app can supersede ghosts and reap closed terminals on this Mac.',
          'Local actions: Open / Focus (location) first, then Copy. Rows leave via SessionEnd, slot supersede, or PID reap — no Dismiss / Approve / submit_input.',
          'location.openURL + focusHint on every snapshot so the panel can jump back to the agent UI.',
          'Alias = free-form machine label (prefer Bonjour LocalHostName on macOS).',
          'Status is never inferred from free-text — only event name + structured fields.',
        ],
      },
      { type: 'h2', text: 'Development' },
      {
        type: 'code',
        lang: 'bash',
        code: `python3 sources/agents/tests/test_nerve_hook.py`,
      },
      {
        type: 'p',
        text: 'sources/agents/nerve_hook.py is a symlink to plugins/nerve/hooks/nerve_hook.py. Prefer marketplace install over the legacy sources/agents/codex/hooks.json template.',
      },
    ],
  },
  {
    slug: 'machines',
    title: 'Machines & remotes',
    lede: 'Settings → Machines manages SSH reverse tunnels so a remote’s loopback ingest reaches the Mac running Nerve.',
    blocks: [
      {
        type: 'p',
        text: 'Machines in Settings are for tunnels only. Any free-form alias in a snapshot is shown in the panel — there is no allow-list.',
      },
      { type: 'h2', text: 'On the Mac running Nerve' },
      {
        type: 'ol',
        items: [
          'Open Settings → Machines',
          'This Mac is always present (alias = hostname short name / Bonjour LocalHostName)',
          'Remote list is loaded from your ~/.ssh/config — use the refresh control to re-read Hosts',
          'Enable a Host, then Connect. Nerve only injects RemoteForward; connection details stay in your SSH config',
        ],
      },
      {
        type: 'callout',
        title: 'known_hosts & OTP / captcha clusters',
        text: 'Host keys come from local known_hosts. For MFA/captcha: run `ssh <alias>` in Terminal first so ControlMaster is up; Connect uses `ssh -O forward` on that master when available.',
      },
      {
        type: 'callout',
        title: 'Alias tip',
        text: 'Use the remote hostname short name as the alias so hooks match without extra setup. Campus DHCP hostnames often differ from Bonjour LocalHostName — mismatch can drop snapshots.',
      },
      { type: 'h2', text: 'On the remote' },
      {
        type: 'ol',
        items: [
          'Install the nerve marketplace plugin',
          'Run sessions as usual',
          'Hooks POST to http://127.0.0.1:17890 — the tunnel forwards that to the host Nerve',
        ],
      },
    ],
  },
  {
    slug: 'status',
    title: 'Status & lifecycle',
    lede: 'Display status is derived from structured facets only. One continuous ribbon; sessions leave on SessionEnd.',
    blocks: [
      { type: 'h2', text: 'Where status lives' },
      {
        type: 'p',
        text: 'The authority is nerve-hub, a small local daemon on fixed loopback 127.0.0.1:17890. Producers POST there; it holds every job and its timeline in memory and fans the whole set out to surfaces over SSE. The menu-bar app is a pure surface — it paints what the hub streams and derives no truth of its own, so the jobs outlive any single window.',
      },
      {
        type: 'ul',
        items: [
          'The port is fixed and not configurable: binding 17890 is itself the single-instance lock, so there is no port field in Settings (only the endpoint, shown for copying) and no NERVE_* env to set.',
          'The app auto-spawns the nerve-hub binary bundled inside Nerve.app when nothing answers on the port, and attaches to the running hub otherwise.',
          'Surfaces are reference-counted. When the last SSE subscriber disconnects, the hub waits out a grace period (30s by default) and exits on its own. Producer POSTs do not keep it alive.',
          'Every surface — menu bar, tmux plugin, plain curl — reads the same frames, so status never depends on which one you have open.',
        ],
      },
      { type: 'h2', text: 'Display statuses' },
      {
        type: 'table',
        headers: ['Status', 'Default', 'Meaning'],
        rows: [
          ['Problem', 'Red', 'Failed / cannot continue'],
          ['Attention', 'Orange', 'Needs input, auth, or decision'],
          ['Waiting', 'Purple', 'Waiting on system / resources / deps'],
          ['Running', 'Blue', 'Actively executing'],
          ['Success', 'Green', 'Monitor waiting for feedback, or ended success'],
          ['Inactive', 'Gray', 'Ready (no turn yet), paused, or unknown'],
        ],
      },
      {
        type: 'p',
        text: 'Open agent sessions stay on the panel while lifecycle is active. On SessionEnd the job is removed immediately. Shell / subagent still running is Running (never Attention). Monitor-only background work is Success green — a phase finished and the stream is waiting for feedback. Your turn (next prompt or approval) is Attention — continue in the agent UI; Nerve never types or approves. SessionStart is Ready/Inactive (not “waiting on you”). Closed terminals on this Mac are reaped via producer PID when present.',
      },
      { type: 'h2', text: 'Main-session lifecycle' },
      {
        type: 'table',
        headers: ['Phase', 'Facet', 'Ribbon'],
        rows: [
          ['Start', 'starting (“Ready”)', 'Inactive'],
          ['Work', 'thinking · tool', 'Running'],
          ['Your turn', 'idle · attention.reason=input', 'Attention'],
          ['Approval in agent', 'waiting · attention.reason=approval', 'Attention'],
          ['Background shell / subagent', 'subagent (+ background_tasks)', 'Running'],
          ['Background monitor only', 'monitor + outcome=partial', 'Success'],
          ['End', 'ended (+ endReason)', 'Leaves panel'],
        ],
      },
      { type: 'h2', text: 'Focus (A+B — not control)' },
      {
        type: 'ul',
        items: [
          'Snapshots carry location.openURL (IDE deep link when hosted in Cursor/VS Code, else workspace file://) and location.focusHint (producer · project · host · path).',
          'Panel primary action is Open / Focus — jumps to the agent workspace. Copy is secondary. No Approve / Type here.',
          'Notification click selects the job, expands it in the panel, and runs Open/Focus.',
          'Attention copy is honest: “Your turn in agent” / “Approval needed in agent” — return to the agent UI to continue.',
        ],
      },
      { type: 'h2', text: 'How a session leaves the panel' },
      {
        type: 'ul',
        items: [
          'SessionEnd (clear, logout, prompt_input_exit, …) — authoritative.',
          'Same UI slot + new SessionStart — previous id ended as superseded (/new · /clear without SessionEnd).',
          'Local producer PID gone — app reaps as process_gone (closed terminal / kill).',
        ],
      },
      { type: 'h2', text: 'Design notes' },
      {
        type: 'ul',
        items: [
          'Jobs, not agents — machines are tunnels; producers report jobs.',
          'Memory-only runtime for jobs, timelines, and pending actions.',
          'Fail-open hooks; fixed loopback ingest; no project env vars.',
          'Out of scope: multi-display ribbons, cloud sync, disk history, in-app agent chat, submit_input / approve from Nerve.',
        ],
      },
    ],
  },
  {
    slug: 'ingest',
    title: 'Ingest API',
    lede: 'Loopback only: http://127.0.0.1:17890. The port is fixed, not a setting. Remotes reach it through SSH reverse tunnels.',
    blocks: [
      {
        type: 'p',
        text: 'This contract belongs to nerve-hub, a small local daemon that holds the jobs. Producers POST into it; the menu-bar app and the tmux plugin are surfaces that read from it. Any alias is accepted — there is no allow-list.',
      },
      {
        type: 'ul',
        items: [
          'The port is not a setting. 17890 is fixed because binding it is the single-instance lock, so producers can hard-code the address and there is no NERVE_* env to read. The macOS app shows the endpoint under Settings → Local Endpoint but offers no port field to change.',
          'You do not start the hub by hand. The menu-bar app spawns the nerve-hub binary bundled inside Nerve.app when nothing answers on the port, and attaches to the already-running hub otherwise.',
        ],
      },
      { type: 'h2', text: 'Endpoints' },
      {
        type: 'table',
        headers: ['Method', 'Path', 'Purpose'],
        rows: [
          ['GET', '/v1/health', 'Liveness'],
          ['GET', '/v1/jobs', 'Current jobs (in memory), each with its timeline'],
          ['GET', '/v1/stream', 'SSE — full frames for surfaces'],
          ['POST', '/v1/snapshot', 'Full job snapshot(s) — requires alias'],
          ['POST', '/v1/events', 'Incremental events — requires alias when creating jobs'],
          ['POST', '/v1/demo', 'Built-in demo jobs'],
          ['POST', '/v1/clear', 'Clear in-memory jobs'],
          ['GET', '/v1/actions/pending?producerId=', 'Poll action queue'],
          ['POST', '/v1/actions/result?producerId=', 'Report action completion'],
        ],
      },
      { type: 'h2', text: 'Snapshot body' },
      {
        type: 'code',
        lang: 'json',
        code: `{
  "alias": "gpu-box",
  "machineKind": "linux",
  "jobs": [
    {
      "id": "claude-code:sess_1",
      "kind": "session",
      "name": "nerve",
      "alias": "gpu-box",
      "producer": {
        "id": "claude-code",
        "name": "Claude Code",
        "kind": "agent.claude"
      },
      "lifecycle": "active",
      "current": { "type": "thinking", "summary": "…" },
      "attention": { "level": "none" },
      "health": "ok",
      "progress": { "kind": "none" },
      "createdAt": "…",
      "updatedAt": "…",
      "version": 1
    }
  ]
}`,
      },
      {
        type: 'ul',
        items: [
          'alias — free-form machine label shown in the panel',
          'kind — job shape (session, build, test, …), not “agent”',
          'producer — who reported the job',
          'name — typically project basename (cwd); status lives in current / attention',
        ],
      },
      { type: 'h2', text: 'Surface stream' },
      {
        type: 'p',
        text: 'GET /v1/stream is Server-Sent Events. Every frame carries the whole truth — there is no delta protocol.',
      },
      {
        type: 'code',
        lang: 'json',
        code: `{ "jobs": [ … ], "departed": [ … ] }`,
      },
      {
        type: 'ul',
        items: [
          'jobs — the authoritative full set. The first frame arrives on connect.',
          'departed — terminal states of jobs evicted since the previous frame (lifecycle ended, endedAt, outcome). A hint so surfaces do not lose the ending; jobs stays the authority.',
          'Reconnecting is resyncing — drop the connection and the next first frame is the full set again.',
          'Every job in a frame has the same shape as one from /v1/jobs, including the timeline the hub keeps for it: up to 40 entries, heartbeats excluded.',
          '?surface=<label> tags the connection in hub logs; it does not change what a frame contains.',
        ],
      },
      {
        type: 'callout',
        title: 'The stream is the lifecycle',
        text: 'An open subscription is a surface being present. nerve-hub counts them: when the last one disconnects it waits out a grace period (30s by default) and exits. Producer POSTs do not keep it alive.',
      },
      { type: 'h2', text: 'Action protocol (producers poll themselves)' },
      {
        type: 'code',
        lang: 'bash',
        code: `curl -s 'http://127.0.0.1:17890/v1/actions/pending?producerId=my-producer'
curl -s -X POST 'http://127.0.0.1:17890/v1/actions/result?producerId=my-producer' \\
  -H 'Content-Type: application/json' \\
  -d '{"id":"<pending-id>","state":"succeeded","message":"ok"}'`,
      },
      {
        type: 'p',
        text: 'There is no /v1/actions/invoke — the hub answers 404. Running an action (Open / Focus, Copy) is a surface capability: the hub echoes the actions a producer declares and derives none of its own.',
      },
      {
        type: 'p',
        text: 'Wire sample in the repo: fixtures/demo_snapshot.json — ./scripts/inject_demo.sh POSTs it to /v1/snapshot.',
      },
    ],
  },
  {
    slug: 'privacy',
    title: 'Privacy',
    lede: 'Private is not a setting. Nerve is a status instrument, not telemetry.',
    blocks: [
      {
        type: 'ul',
        items: [
          'Jobs, timelines, and pending actions are memory-only for the current process',
          'Quitting Nerve clears runtime state completely',
          'Only preferences (machines, colors, notifications, coach flags) use UserDefaults',
          'Tunnel Hosts prefer your existing ~/.ssh/config + known_hosts; Nerve’s managed block only adds RemoteForward',
          'Ingest never leaves 127.0.0.1',
          'Remotes only via SSH reverse tunnels you configure',
          'Hooks fail open — agents never block on Nerve',
        ],
      },
      {
        type: 'callout',
        text: 'There is no “save names/summaries” toggle because nothing is persisted for jobs. Demo and clear are HTTP ingest only.',
      },
    ],
  },
];

export function getDocPage(slug: string): DocPage | undefined {
  return docPages.find((p) => p.slug === slug);
}
