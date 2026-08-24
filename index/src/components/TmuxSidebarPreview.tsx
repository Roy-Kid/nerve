import { jobs, statusMeta, type StatusTone } from '../config';
import { cn } from '../lib/utils';
import { useLocale } from '../i18n/locale';

const selectedId = jobs.find((job) => job.status === 'attention')?.id ?? jobs[0].id;

function tmuxFilterChips(statuses: readonly StatusTone[]) {
  const n = (status: StatusTone) => statuses.filter((item) => item === status).length;
  return [
    { icon: '≡', count: statuses.length, color: null as string | null },
    { icon: '●', count: n('running'), color: statusMeta.running.color },
    { icon: '◎', count: n('monitor'), color: statusMeta.monitor.color },
    { icon: '◐', count: n('attention'), color: statusMeta.attention.color },
    { icon: '○', count: n('inactive') + n('success'), color: statusMeta.inactive.color },
    { icon: '✕', count: n('problem'), color: statusMeta.problem.color },
  ];
}

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
  const rows = jobs.map((job, index) => ({
    ...job,
    ...t.preview.tmux.jobs[index],
    active: job.id === selectedId,
  }));
  const chips = tmuxFilterChips(jobs.map((job) => job.status));

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
            {chips.map((chip) => {
              const Tag = chip.count > 0 ? 'b' : 'span';
              return (
                <Tag key={chip.icon} style={chip.color ? { color: chip.color } : undefined}>
                  {chip.icon}
                  {chip.count}
                </Tag>
              );
            })}
          </div>
          <div className="tmux-demo-filter" aria-hidden="true">▾ {t.preview.tmux.filter}</div>
          <ul className="tmux-demo-jobs">
            {rows.map((job) => (
              <li key={job.id} className={cn(job.active && 'is-active')}>
                <i style={{ background: statusMeta[job.status].color }} aria-hidden="true" />
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
