import { useEffect, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Menu, X } from 'lucide-react';
import { site } from '../config';
import { useLocale } from '../i18n/locale';
import { cn } from '../lib/utils';
import { GitHubIcon } from './Icons';
import { LanguageToggle } from './LanguageToggle';

type NavVariant = 'hub' | 'docs';

type NavProps = {
  variant?: NavVariant;
};

/** Below this the links collapse into the sheet. Not on Tailwind's scale, so
 *  it is the theme's own `lap` breakpoint. */
const linkRow = 'flex items-center justify-center gap-1 max-lap:hidden';

const navLink =
  'focus-ring rounded-full px-2.5 py-1.5 text-xs/[1.55] font-[450] text-label ' +
  'transition-[opacity,background-color] duration-[140ms] hover:opacity-100 motion-reduce:transition-none';

const sheetLink =
  'focus-ring flex min-h-[52px] items-center justify-between border-b border-black/8 ' +
  'py-2.5 text-[25px] font-semibold tracking-[-0.035em] text-label';

export function Nav({ variant = 'hub' }: NavProps) {
  const [scrolled, setScrolled] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const location = useLocation();
  const path = location.pathname;
  const { t } = useLocale();
  const onHub = variant === 'hub' && path === '/';

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => {
    setMobileOpen(false);
  }, [path]);

  useEffect(() => {
    if (!mobileOpen) return;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setMobileOpen(false);
    };
    document.addEventListener('keydown', closeOnEscape);
    return () => document.removeEventListener('keydown', closeOnEscape);
  }, [mobileOpen]);

  const productLinks = [
    { to: '/', label: t.nav.home, match: (p: string) => p === '/' },
    { to: '/docs', label: t.nav.docs, match: (p: string) => p.startsWith('/docs') },
  ];

  return (
    <header
      className={cn(
        'fixed inset-x-0 top-0 z-50 h-12 text-label',
        'transition-[background-color,border-color,backdrop-filter] duration-[180ms] motion-reduce:transition-none',
        scrolled || !onHub || mobileOpen
          ? 'border-b border-black/8 bg-page/80 backdrop-blur-[22px] backdrop-saturate-[1.8]'
          : 'border-b border-transparent bg-transparent',
        mobileOpen &&
          'max-lap:h-auto max-lap:min-h-dvh max-lap:bg-page/95 max-lap:backdrop-saturate-[1.6]',
      )}
    >
      <div
        className={cn(
          'mx-auto grid h-full w-[calc(100%-2*var(--page-gutter))] max-w-page',
          'grid-cols-[1fr_auto_1fr] items-center gap-6',
          'max-lap:flex max-lap:justify-between',
        )}
      >
        <Link
          to="/"
          className="focus-ring group inline-flex w-fit items-center gap-2 text-sm/[1.55] font-[650] tracking-[-0.02em] text-label"
        >
          <img
            src={`${import.meta.env.BASE_URL}logo.png`}
            alt=""
            width={24}
            height={24}
            className="rounded-md animate-mark-arrive group-hover:animate-mark-pop motion-reduce:animate-none"
          />
          <span>{site.name}</span>
        </Link>

        <nav className={linkRow} aria-label={t.nav.productNavigation}>
          {productLinks.map((item) => (
            <Link
              key={item.to}
              to={item.to}
              aria-current={item.match(path) ? 'page' : undefined}
              className={cn(
                navLink,
                item.match(path) ? 'bg-black/5 opacity-100' : 'opacity-[0.68]',
              )}
            >
              {item.label}
            </Link>
          ))}
        </nav>

        <div className="flex items-center justify-end gap-[3px]">
          <LanguageToggle />
          <a
            href={site.github}
            target="_blank"
            rel="noreferrer"
            className={cn(
              'focus-ring inline-flex size-8 items-center justify-center rounded-full text-label',
              'opacity-[0.72] transition-[opacity,background-color] duration-[140ms]',
              'hover:bg-black/5 hover:opacity-100 motion-reduce:transition-none max-lap:hidden',
            )}
            aria-label={t.nav.github}
          >
            <GitHubIcon className="size-[17px]" />
          </a>
          <Link
            to="/docs/get-started"
            className={cn(
              'focus-ring ml-[5px] inline-flex min-h-7 items-center justify-center rounded-full',
              'bg-blue px-3 py-[5px] text-xs font-[550] leading-none text-white',
              'transition-[background-color,transform] duration-[140ms]',
              'hover:-translate-y-px hover:bg-blue-pressed motion-reduce:transition-none max-lap:hidden',
            )}
          >
            {t.nav.get}
          </Link>
          <button
            type="button"
            className={cn(
              'focus-ring hidden size-8 items-center justify-center rounded-full text-label',
              'opacity-[0.72] transition-[opacity,background-color] duration-[140ms]',
              'hover:bg-black/5 hover:opacity-100 motion-reduce:transition-none',
              'max-lap:inline-flex [&_svg]:size-[18px]',
            )}
            aria-label={mobileOpen ? t.nav.closeMenu : t.nav.openMenu}
            aria-controls="mobile-product-nav"
            aria-expanded={mobileOpen}
            onClick={() => setMobileOpen((open) => !open)}
          >
            {mobileOpen ? <X aria-hidden="true" /> : <Menu aria-hidden="true" />}
          </button>
        </div>
      </div>
      {mobileOpen ? (
        <nav
          id="mobile-product-nav"
          className="hidden max-lap:flex max-lap:flex-col max-lap:px-[var(--page-gutter)] max-lap:pt-[26px] max-lap:pb-10"
          aria-label={t.nav.mobileNavigation}
        >
          {productLinks.map((item) => (
            <Link
              key={item.to}
              to={item.to}
              className={sheetLink}
              onClick={() => setMobileOpen(false)}
            >
              <span className={cn(item.match(path) && 'text-blue')}>{item.label}</span>
              <span aria-hidden="true" className="font-normal text-label-3">
                ›
              </span>
            </Link>
          ))}
          <a href={site.github} target="_blank" rel="noreferrer" className={sheetLink}>
            <span>GitHub</span>
            <span aria-hidden="true" className="font-normal text-label-3">
              ↗
            </span>
          </a>
        </nav>
      ) : null}
    </header>
  );
}
