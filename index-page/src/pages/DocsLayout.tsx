import { NavLink, Outlet } from 'react-router-dom';
import { Footer } from '../components/Footer';
import { Nav } from '../components/Nav';
import { docNav } from '../docs/content';

export function DocsLayout() {
  return (
    <div className="docs-shell">
      <Nav variant="docs" />
      <div className="docs-frame">
        <aside className="docs-side" aria-label="Documentation">
          <p className="docs-side-label">Docs</p>
          <nav className="docs-side-nav">
            <NavLink to="/docs" end className={sideLinkClass}>
              Overview
            </NavLink>
            {docNav.map((item) => (
              <NavLink key={item.slug} to={`/docs/${item.slug}`} className={sideLinkClass}>
                {item.title}
              </NavLink>
            ))}
          </nav>
        </aside>
        <div className="docs-main">
          <Outlet />
        </div>
      </div>
      <Footer />
    </div>
  );
}

function sideLinkClass({ isActive }: { isActive: boolean }) {
  return `docs-side-link${isActive ? ' is-active' : ''}`;
}
