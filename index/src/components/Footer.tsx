import { Link } from 'react-router-dom';
import { getTmuxGuidePath, site } from '../config';
import { useLocale } from '../i18n/locale';

const footerLink =
  'focus-ring text-[13px] text-label-2 transition-colors duration-[140ms] ' +
  'hover:text-label motion-reduce:transition-none';

export function Footer() {
  const year = new Date().getFullYear();
  const { locale, t } = useLocale();
  const tmuxGuidePath = getTmuxGuidePath(locale);

  return (
    <footer className="border-t border-black/8 bg-page px-[var(--page-gutter)] pt-[30px] pb-9 text-label">
      <div className="mx-auto flex w-full max-w-page flex-wrap items-center justify-between gap-x-8 gap-y-[18px] max-lap:flex-col max-lap:items-start">
        <Link
          to="/"
          className="focus-ring group inline-flex w-fit items-center gap-2 text-sm/[1.55] font-[650] tracking-[-0.02em] text-label"
        >
          <img
            src={`${import.meta.env.BASE_URL}logo.png`}
            alt=""
            width={22}
            height={22}
            className="animate-mark-arrive group-hover:animate-mark-pop motion-reduce:animate-none"
          />
          <span>{site.name}</span>
        </Link>
        <nav
          className="flex flex-wrap gap-x-5 gap-y-2 max-lap:flex-col max-lap:items-start max-lap:gap-2.5"
          aria-label={t.nav.footerNavigation}
        >
          <a href={site.github} target="_blank" rel="noreferrer" className={footerLink}>
            GitHub
          </a>
          <Link to="/macos" className={footerLink}>
            macOS
          </Link>
          <Link to={tmuxGuidePath} className={footerLink}>
            tmux
          </Link>
          <Link to="/docs" className={footerLink}>
            {t.nav.docs}
          </Link>
          <Link to="/docs/get-started" className={footerLink}>
            {t.footer.download}
          </Link>
        </nav>
      </div>
      <p className="mx-auto mt-4 w-full max-w-page border-t border-black/6 pt-4 text-xs/[1.55] text-label-3">
        © {year} Nerve — {t.footer.tagline}
      </p>
    </footer>
  );
}
