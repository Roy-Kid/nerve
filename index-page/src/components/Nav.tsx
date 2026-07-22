import { useEffect, useState } from 'react';
import { site } from '../config';
import { GitHubIcon } from './Icons';

export function Nav() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 24);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <header className={`nav${scrolled ? ' is-on' : ''}`}>
      <a className="nav-brand" href="#top">
        <img src={`${import.meta.env.BASE_URL}logo.png`} alt="" width={28} height={28} />
        <span>{site.name}</span>
      </a>

      <div className="nav-links" aria-label="Sections">
        <a href="#story">Story</a>
        <a href="#signal">Signal</a>
        <a href="#sources">Sources</a>
        <a href="#quiet">Privacy</a>
      </div>

      <div className="nav-actions">
        <a
          className="link-quiet"
          href={site.github}
          target="_blank"
          rel="noreferrer"
        >
          <GitHubIcon width={16} height={16} />
          <span>GitHub</span>
        </a>
        <a className="chip-cta" href="#get">
          Get Nerve
        </a>
      </div>
    </header>
  );
}
