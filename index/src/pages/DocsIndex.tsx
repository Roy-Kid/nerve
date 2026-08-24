import { Link } from 'react-router-dom';
import { getDocNav } from '../docs/content';
import { useLocale } from '../i18n/locale';
import { docLede, docTitle, eyebrow } from '../lib/ui';

export function DocsIndex() {
  const { locale, t } = useLocale();
  const docNav = getDocNav(locale);

  return (
    <article className="pt-[0.2rem] pb-8">
      <header className="mb-[1.8rem]">
        <p className={eyebrow}>{t.docsUi.indexEyebrow}</p>
        <h1 className={docTitle}>{t.docsUi.indexTitle}</h1>
        <p className={docLede}>{t.docsUi.indexLede}</p>
      </header>

      <ul className="m-0 grid list-none grid-cols-2 gap-[0.85rem] p-0 max-wide:grid-cols-1">
        {docNav.map((item) => (
          <li key={item.slug}>
            <Link
              to={`/docs/${item.slug}`}
              className="focus-ring flex h-full flex-col gap-[0.35rem] rounded-[1.15rem] border border-[rgb(56_79_116/10%)] bg-white/74 px-[1.2rem] pt-[1.15rem] pb-[1.25rem] shadow-[0_12px_36px_rgb(62_84_121/6%)] transition-[transform,box-shadow,border-color] duration-[180ms] ease-page hover:-translate-y-0.5 hover:border-[rgb(77_134_247/28%)] hover:shadow-[0_16px_44px_rgb(62_84_121/10%)] motion-reduce:transition-none"
            >
              <strong className="font-display text-[1.05rem] tracking-[-0.02em]">
                {item.title}
              </strong>
              <span className="text-[0.9rem] leading-[1.45] text-ink-dim">{item.summary}</span>
            </Link>
          </li>
        ))}
      </ul>
    </article>
  );
}
