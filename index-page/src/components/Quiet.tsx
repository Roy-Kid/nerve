import { statusMeta } from '../config';

const points = [
  'Jobs, timelines, pending actions — memory only',
  'Quit clears runtime state completely',
  'Preferences stay in UserDefaults on this Mac',
  'Ingest never leaves 127.0.0.1',
  'Remotes only via SSH reverse tunnels you configure',
  'Hooks fail open — agents never block on Nerve',
];

export function Quiet() {
  return (
    <section className="quiet" id="quiet" aria-labelledby="quiet-title">
      <div className="quiet-wrap">
        <div className="quiet-type">
          <p className="eyebrow">Privacy</p>
          <h2 id="quiet-title" className="display display--sm">
            Private is not
            <br />
            a setting.
          </h2>
          <p className="lede lede--tight">
            Nerve is a status instrument, not telemetry. What runs on your machines
            stays on your machines.
          </p>
        </div>

        <ul className="quiet-points">
          {points.map((p) => (
            <li key={p}>{p}</li>
          ))}
        </ul>
      </div>

      <div className="palette" aria-label="Status colors">
        {(
          ['problem', 'attention', 'waiting', 'running', 'success', 'inactive'] as const
        ).map((key) => (
          <div key={key} className="palette-swatch">
            <span style={{ background: statusMeta[key].color }} />
            <strong>{statusMeta[key].label}</strong>
            <em>{statusMeta[key].hint}</em>
          </div>
        ))}
      </div>
    </section>
  );
}
