import { NavLink, Outlet } from 'react-router-dom';
import { Footer } from '../components/Footer';
import { Nav } from '../components/Nav';
import { getDocNav } from '../docs/content';
import { useLocale } from '../i18n/locale';
import { cn } from '../lib/utils';

const sideLink =
  'focus-ring block rounded-[0.55rem] px-[0.55rem] py-[0.48rem] text-[0.9rem] ' +
  'font-[550] transition-[background-color,color] duration-150 motion-reduce:transition-none';

export function DocsLayout() {
  const { locale, t } = useLocale();
  const docNav = getDocNav(locale);

  return (
    <div className="flex min-h-screen flex-col bg-page">
      <Nav variant="docs" />
      <div className="mx-auto mt-20 mb-12 grid w-[calc(100%-2*var(--page-gutter))] max-w-page flex-1 grid-cols-[13.5rem_minmax(0,1fr)] items-start gap-[clamp(1.5rem,4vw,3rem)] max-wide:mt-[4.8rem] max-wide:grid-cols-1">
        <aside
          className="sticky top-[5.2rem] rounded-[1.15rem] border border-[rgb(56_79_116/10%)] bg-white/72 px-[0.85rem] py-[0.9rem] shadow-card backdrop-blur-[14px] max-wide:static"
          aria-label={t.docsUi.sidebarLabel}
        >
          <p className="mt-0 mr-0 mb-[0.55rem] ml-[0.35rem] text-[0.72rem] font-[650] tracking-[0.08em] text-ink-faint uppercase">
            {t.docsUi.protocol}
          </p>
          <nav className="flex flex-col gap-[0.15rem] max-wide:grid max-wide:grid-cols-2 max-wide:gap-1">
            <NavLink to="/docs" end className={sideLinkClass}>
              {t.docsUi.overview}
            </NavLink>
            {docNav.map((item) => (
              <NavLink key={item.slug} to={`/docs/${item.slug}`} className={sideLinkClass}>
                {item.title}
              </NavLink>
            ))}
          </nav>
        </aside>
        <div className="min-w-0">
          <Outlet />
        </div>
      </div>
      <Footer />
    </div>
  );
}

function sideLinkClass({ isActive }: { isActive: boolean }) {
  return cn(
    sideLink,
    isActive
      ? 'bg-[rgb(77_134_247/12%)] font-[650] text-[#1f4fa8]'
      : 'text-ink-dim hover:bg-[rgb(77_134_247/8%)] hover:text-ink',
  );
}
