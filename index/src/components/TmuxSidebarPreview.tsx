import { statusMeta } from '../config';
import { cn } from '../lib/utils';
import { useLocale } from '../i18n/locale';

const jobPresentation = [
  { tone: 'running', active: false },
  { tone: 'attention', active: true },
  { tone: 'success', active: false },
  { tone: 'waiting', active: false },
  { tone: 'inactive', active: false },
] as const;

// The status palette has one owner (`config.ts`); the preview must not paint
// the same status a different green than the ribbon beside it.
const toneColor: Record<(typeof jobPresentation)[number]['tone'], string> = {
  running: statusMeta.running.color,
  success: statusMeta.success.color,
  inactive: statusMeta.inactive.color,
  attention: statusMeta.attention.color,
  waiting: statusMeta.waiting.color,
};

type TmuxSidebarPreviewProps = {
  /** How large the surrounding section wants the terminal.
   *  `hero` fills a page-wide band, `card` sits in a two-up grid. */
  variant?: 'default' | 'hero' | 'card';
  className?: string;
};

export function TmuxSidebarPreview({
  variant = 'default',
  className,
}: TmuxSidebarPreviewProps) {
  const { t } = useLocale();
  const jobs = jobPresentation.map((presentation, index) => ({
    ...presentation,
    ...t.preview.tmux.jobs[index],
  }));

  return (
    <div
      className={cn(
        'tmux-preview tmux-demo',
        variant !== 'default' && `tmux-preview--${variant}`,
        className,
      )}
      aria-label={t.preview.tmux.label}
    >
      <div className="tmux-demo-chrome" aria-hidden="true">
        <div className="tmux-demo-title">
          <span className="tmux-preview-dot tmux-preview-dot--red" />
          <span className="tmux-preview-dot tmux-preview-dot--amber" />
          <span className="tmux-preview-dot tmux-preview-dot--green" />
          <span>roykid — tmux</span>
        </div>
      </div>

      <div className="tmux-demo-workspace">
        <aside className="tmux-demo-sidebar">
          <div className="tmux-demo-counts" aria-hidden="true">
            <b>≡5</b><b>●3</b><span>◎0</span><b>○1</b><span>×0</span>
          </div>
          <div className="tmux-demo-filter" aria-hidden="true">▾ {t.preview.tmux.filter}</div>
          <ul className="tmux-demo-jobs">
            {jobs.map((job) => (
              <li key={`${job.name}-${job.detail}`} className={cn(job.active && 'is-active')}>
                <i style={{ background: toneColor[job.tone] }} aria-hidden="true" />
                <strong>{job.name}</strong>
                <span>{job.detail}</span>
                <time>{job.time}</time>
              </li>
            ))}
          </ul>
          <div className="tmux-demo-activity">
            <span>{t.preview.tmux.activity}</span>
            <strong>{t.preview.tmux.reviewRequested}</strong>
          </div>
        </aside>

        <div className="tmux-demo-terminal" aria-hidden="true">
          <div className="tmux-demo-diff">
            <span>3077 <i>−</i></span><code> .hub-main {'{'}</code>
            <span>3078 <i>−</i></span><code>   padding-top: 4.8rem;</code>
            <span>3079 <i>−</i></span><code>{'}'}</code>
          </div>
          <div className="tmux-demo-log">
            <p><i /> <strong>{t.preview.tmux.checkoutReady}</strong></p>
            <code>✓ {t.preview.tmux.implementationDone}</code>
            <code>✓ {t.preview.tmux.testsPassed}</code>
            <code>✓ {t.preview.tmux.waitingForReview}</code>
          </div>
          <div className="tmux-demo-prompt">› {t.preview.tmux.prompt}</div>
          <div className="tmux-demo-status">
            <b>[nerve]</b>
            <span>0:node- 1:node*</span>
            <em>"nerve"</em>
          </div>
        </div>
      </div>
    </div>
  );
}
