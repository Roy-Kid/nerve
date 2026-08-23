import { Link, Navigate, useParams } from 'react-router-dom';
import { DocBlocks } from '../components/docs/DocBlocks';
import { getDocNav, getDocPage } from '../docs/content';
import { useLocale } from '../i18n/locale';
import { cn } from '../lib/utils';
import { docLede, docTitle, eyebrow } from '../lib/ui';

const pagerLink =
  'focus-ring flex flex-col gap-[0.2rem] rounded-[0.95rem] border border-[rgb(56_79_116/10%)] ' +
  'bg-white/70 px-4 py-[0.9rem] transition-[border-color] duration-150 ' +
  'hover:border-[rgb(77_134_247/30%)] motion-reduce:transition-none';

const pagerKicker = 'text-[0.72rem] font-[650] tracking-[0.04em] text-ink-faint uppercase';
const pagerTitle = 'text-[0.98rem] tracking-[-0.02em]';

export function DocPage() {
  const { slug = '' } = useParams();
  const { locale, t } = useLocale();
  const docNav = getDocNav(locale);
  const page = getDocPage(slug, locale);

  if (!page) {
    return <Navigate to="/docs" replace />;
  }

  const idx = docNav.findIndex((d) => d.slug === page.slug);
  const prev = idx > 0 ? docNav[idx - 1] : null;
  const next = idx >= 0 && idx < docNav.length - 1 ? docNav[idx + 1] : null;

  return (
    <article className="pt-[0.2rem] pb-8">
      <header className="mb-[1.8rem]">
        <p className={eyebrow}>{t.docsUi.eyebrow}</p>
        <h1 className={docTitle}>{page.title}</h1>
        <p className={docLede}>{page.lede}</p>
      </header>

      <DocBlocks blocks={page.blocks} />

      <nav
        className="mt-10 grid grid-cols-2 gap-[0.85rem] border-t border-[rgb(52_75_114/10%)] pt-[1.4rem] max-wide:grid-cols-1"
        aria-label={t.docsUi.pagerLabel}
      >
        {prev ? (
          <Link to={`/docs/${prev.slug}`} className={pagerLink}>
            <span className={pagerKicker}>{t.docsUi.previous}</span>
            <strong className={pagerTitle}>{prev.title}</strong>
          </Link>
        ) : (
          <span />
        )}
        {next ? (
          <Link
            to={`/docs/${next.slug}`}
            className={cn(pagerLink, 'justify-self-end text-right max-wide:justify-self-stretch max-wide:text-left')}
          >
            <span className={pagerKicker}>{t.docsUi.next}</span>
            <strong className={pagerTitle}>{next.title}</strong>
          </Link>
        ) : (
          <span />
        )}
      </nav>
    </article>
  );
}
