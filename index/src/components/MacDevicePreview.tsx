import { jobs } from '../config';
import { cn } from '../lib/utils';
import type { StatusRibbonSegment } from '../lib/statusRibbon';
import { StatusRibbonBand } from './StatusRibbonBand';
import { useLocale } from '../i18n/locale';

const previewRibbon: StatusRibbonSegment[] = jobs.map((job) => ({
  id: job.id,
  status: job.status,
  weight: 1,
}));

const runningCount = jobs.filter((job) => job.status === 'running').length;
const attentionCount = jobs.filter((job) => job.status === 'attention').length;

type MacDevicePreviewProps = {
  variant?: 'default' | 'hero' | 'card';
  showKicker?: boolean;
  className?: string;
};

export function MacDevicePreview({
  variant = 'default',
  showKicker = false,
  className,
}: MacDevicePreviewProps) {
  const { t } = useLocale();
  const previewJobs = jobs.map((job, index) => ({
    id: job.id,
    tone: job.status,
    ...t.preview.mac.jobs[index],
  }));

  return (
    <div
      className={cn(
        'preview-shell',
        variant !== 'default' && `preview-shell--${variant}`,
        className,
      )}
    >
      {showKicker ? (
        <p className="preview-kicker">
          <span aria-hidden="true" /> {t.preview.mac.livePreview}
        </p>
      ) : null}

      <div className={cn('mac-device', variant === 'hero' && 'mac-device--hero')}>
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
              <code>{t.preview.mac.terminalReady}</code>
            </div>
          </div>

          <div className="desktop-menubar">
            <div className="desktop-menubar-left">
              <span className="desktop-apple" aria-hidden="true">
                
              </span>
              <strong>{t.preview.mac.finder}</strong>
              <span>{t.preview.mac.file}</span>
              <span>{t.preview.mac.edit}</span>
              <span>{t.preview.mac.view}</span>
            </div>

            <div className="desktop-menubar-right">
              <div className="desktop-ribbon" aria-label={t.preview.mac.ribbonLabel}>
                <StatusRibbonBand segments={previewRibbon} className="desktop-ribbon-fill" />
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

          <section className="nerve-popover" aria-label={t.preview.mac.panelLabel}>
            <header className="popover-toolbar">
              <div className="popover-counts" aria-label={t.preview.mac.countsLabel}>
                <span className="count-running">
                  <i aria-hidden="true">▶</i> {runningCount}
                </span>
                <span className="count-attention">
                  <i aria-hidden="true">!</i> {attentionCount}
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
                <li key={job.id}>
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
  );
}
