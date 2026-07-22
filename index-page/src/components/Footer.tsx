import { site } from '../config';

export function Footer() {
  const year = new Date().getFullYear();
  return (
    <footer className="site-footer">
      <div className="footer-row">
        <a className="nav-brand" href="#top">
          <img src={`${import.meta.env.BASE_URL}logo.png`} alt="" width={22} height={22} />
          <span>{site.name}</span>
        </a>
        <nav className="footer-nav" aria-label="Footer">
          <a href={site.github} target="_blank" rel="noreferrer">
            GitHub
          </a>
          <a href={site.docs} target="_blank" rel="noreferrer">
            Docs
          </a>
          <a href={site.pluginDocs} target="_blank" rel="noreferrer">
            Plugins
          </a>
          <a href="#get">Download</a>
        </nav>
      </div>
      <p className="footer-copy">
        © {year} Nerve — agents keep working; the ribbon just listens.
      </p>
    </footer>
  );
}
