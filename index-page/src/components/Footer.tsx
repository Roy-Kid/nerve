import { Link } from 'react-router-dom';
import { site } from '../config';

export function Footer() {
  const year = new Date().getFullYear();
  return (
    <footer className="site-footer">
      <div className="footer-row">
        <Link className="nav-brand" to="/">
          <img src={`${import.meta.env.BASE_URL}logo.png`} alt="" width={22} height={22} />
          <span>{site.name}</span>
        </Link>
        <nav className="footer-nav" aria-label="Footer">
          <a href={site.github} target="_blank" rel="noreferrer">
            GitHub
          </a>
          <Link to="/docs">Docs</Link>
          <Link to="/docs/plugin">Plugins</Link>
          <Link to="/#get">Download</Link>
        </nav>
      </div>
      <p className="footer-copy">
        © {year} Nerve — agents keep working; the ribbon just listens.
      </p>
    </footer>
  );
}
