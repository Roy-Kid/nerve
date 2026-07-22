import { site } from '../config';
import { usePointer } from '../hooks/usePointer';
import { usePrefersReducedMotion } from '../hooks/usePrefersReducedMotion';
import { AppleIcon, GitHubIcon } from './Icons';

const previewJobs = [
  {
    tone: 'problem',
    name: 'Deploy preview',
    detail: 'Health check failed',
    time: '8 min',
  },
  {
    tone: 'attention',
    name: 'Unit tests',
    detail: 'Approval required',
    time: '1 min',
  },
  {
    tone: 'waiting',
    name: 'Nerve',
    detail: 'Waiting for input',
    time: '10 sec',
  },
  {
    tone: 'running',
    name: 'Claude Code',
    detail: 'Editing website',
    time: '18 sec',
  },
  {
    tone: 'success',
    name: 'Build archive',
    detail: 'Finished cleanly',
    time: '2 min',
  },
  {
    tone: 'inactive',
    name: 'Local watcher',
    detail: 'No recent signal',
    time: '12 min',
  },
] as const;

export function Stage() {
  const pointer = usePointer();
  const reduced = usePrefersReducedMotion();

  const bloomX = reduced ? 72 : 55 + pointer.x * 30;
  const bloomY = reduced ? 28 : 18 + pointer.y * 28;

  return (
    <section className="stage" id="top" aria-labelledby="hero-title">
      <div
        className="stage-bloom"
        style={{
          background: `
            radial-gradient(ellipse 52% 42% at ${bloomX}% ${bloomY}%, rgba(77,141,255,0.26), transparent 61%),
            radial-gradient(ellipse 42% 36% at ${100 - bloomX}% ${bloomY + 18}%, rgba(149,103,237,0.19), transparent 57%),
            radial-gradient(ellipse 35% 30% at ${bloomX - 24}% 72%, rgba(85,207,117,0.15), transparent 52%),
            radial-gradient(ellipse 32% 27% at 84% 76%, rgba(255,159,67,0.14), transparent 52%),
            radial-gradient(ellipse 28% 24% at 12% 88%, rgba(87,199,235,0.12), transparent 54%),
            radial-gradient(ellipse 26% 22% at 70% 5%, rgba(255,102,95,0.1), transparent 52%)
          `,
        }}
        aria-hidden="true"
      />

      <div className="stage-grid" aria-hidden="true" />

      <div className="stage-inner">
        <div className="stage-copy">
          <p className="eyebrow">
            <span className="eyebrow-pulse" aria-hidden="true" />
            macOS · menu bar · local-first
          </p>

          <h1 id="hero-title" className="display">
            <span className="display-line">{site.headline[0]}</span>
            <span className="display-line display-line--accent">{site.headline[1]}</span>
          </h1>

          <p className="lede">{site.subhead}</p>

          <div className="stage-ctas">
            <a
              className="btn btn-solid"
              href={site.appStoreReady ? site.appStore : '#get'}
              target={site.appStoreReady ? '_blank' : undefined}
              rel={site.appStoreReady ? 'noreferrer' : undefined}
            >
              <AppleIcon width={18} height={18} />
              {site.appStoreReady ? 'App Store' : 'App Store · soon'}
            </a>
            <a
              className="btn btn-line"
              href={site.github}
              target="_blank"
              rel="noreferrer"
            >
              <GitHubIcon width={18} height={18} />
              Source on GitHub
            </a>
          </div>
        </div>

        <div className="stage-demo" aria-label="Live ribbon preview">
          <div className="hero-identity">
            <div className="hero-mark" aria-hidden="true">
              <span className="hero-wave hero-wave--one" />
              <span className="hero-wave hero-wave--two" />
              <span className="hero-wave hero-wave--three" />
              <span className="hero-orbit hero-orbit--outer" />
              <span className="hero-orbit hero-orbit--inner" />
              <span className="hero-node hero-node--blue" />
              <span className="hero-node hero-node--cyan" />
              <span className="hero-node hero-node--green" />
              <span className="hero-node hero-node--amber" />
              <span className="hero-node hero-node--red" />
              <span className="hero-node hero-node--violet" />
              <img
                src={`${import.meta.env.BASE_URL}logo.png`}
                alt=""
                width={368}
                height={368}
                className="hero-logo"
              />
            </div>

          </div>

          <div className="preview-shell">
            <p className="preview-kicker">
              <span aria-hidden="true" /> Live preview
            </p>

            <div className="mac-device">
              <div className="mac-screen">
                <div className="desktop-wallpaper" aria-hidden="true">
                  <div className="desktop-window desktop-window--code">
                    <span className="desktop-window-bar">
                      <i />
                      <i />
                      <i />
                    </span>
                    <span className="desktop-code-line desktop-code-line--long" />
                    <span className="desktop-code-line" />
                    <span className="desktop-code-line desktop-code-line--short" />
                    <span className="desktop-code-line desktop-code-line--long" />
                  </div>
                  <div className="desktop-window desktop-window--terminal">
                    <span className="desktop-window-bar">
                      <i />
                      <i />
                      <i />
                    </span>
                    <code>$ npm run build</code>
                    <code>ready · built in 0.10 s</code>
                  </div>
                </div>

                <div className="desktop-menubar">
                  <div className="desktop-menubar-left">
                    <span className="desktop-apple" aria-hidden="true">
                      
                    </span>
                    <strong>Finder</strong>
                    <span>File</span>
                    <span>Edit</span>
                    <span>View</span>
                  </div>

                  <div className="desktop-menubar-right">
                    <div className="desktop-ribbon" aria-label="Nerve status ribbon">
                      <span className="desktop-ribbon-fill" />
                    </div>
                    <span className="desktop-menu-icon" aria-hidden="true">
                      ◫
                    </span>
                    <span className="desktop-menu-icon" aria-hidden="true">
                      ◒
                    </span>
                    <span className="desktop-menu-icon" aria-hidden="true">
                      ☼
                    </span>
                    <span className="desktop-clock">9:41</span>
                  </div>
                </div>

                <section className="nerve-popover" aria-label="Nerve status panel preview">
                  <header className="popover-toolbar">
                    <div className="popover-counts" aria-label="Status counts">
                      <span className="count-running">
                        <i aria-hidden="true">▶</i> 1
                      </span>
                      <span className="count-attention">
                        <i aria-hidden="true">!</i> 1
                      </span>
                    </div>
                    <div className="popover-actions" aria-hidden="true">
                      <span>⇅</span>
                      <span>↻</span>
                      <span>⌫</span>
                    </div>
                  </header>

                  <div className="preview-machine">STUDIO-MAC</div>

                  <ul className="preview-jobs">
                    {previewJobs.map((job) => (
                      <li key={job.name}>
                        <i className={`job-dot job-dot--${job.tone}`} aria-hidden="true" />
                        <strong>{job.name}</strong>
                        <span>{job.detail}</span>
                        <time>{job.time}</time>
                        <b aria-hidden="true">›</b>
                      </li>
                    ))}
                  </ul>

                </section>

                <span className="desktop-camera" aria-hidden="true" />
              </div>

              <div className="mac-base" aria-hidden="true">
                <span />
              </div>
            </div>

          </div>
        </div>
      </div>

      <a className="scroll-cue" href="#story" aria-label="Scroll to story">
        <span />
        Scroll
      </a>
    </section>
  );
}
