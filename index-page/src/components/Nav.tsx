import { useEffect, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { site } from '../config';
import { GitHubIcon } from './Icons';

type NavProps = {
  /** Home marketing nav vs docs chrome. */
  variant?: 'home' | 'docs';
};

export function Nav({ variant = 'home' }: NavProps) {
  const [scrolled, setScrolled] = useState(false);
  const location = useLocation();
  const onHome = location.pathname === '/';

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 24);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <header className={`nav${scrolled ? ' is-on' : ''}${variant === 'docs' ? ' nav--docs' : ''}`}>
      <Link className="nav-brand" to="/">
        <img src={`${import.meta.env.BASE_URL}logo.png`} alt="" width={28} height={28} />
        <span>{site.name}</span>
      </Link>

      <div className="nav-links" aria-label="Sections">
        {onHome ? (
          <>
            <a href="#story">Story</a>
            <a href="#signal">Signal</a>
            <a href="#sources">Sources</a>
            <a href="#quiet">Privacy</a>
          </>
        ) : (
          <>
            <Link to="/#story">Story</Link>
            <Link to="/#signal">Signal</Link>
            <Link to="/#sources">Sources</Link>
            <Link to="/#quiet">Privacy</Link>
          </>
        )}
        <Link to="/docs" className={location.pathname.startsWith('/docs') ? 'is-active' : undefined}>
          Docs
        </Link>
      </div>

      <div className="nav-actions">
        <a className="link-quiet" href={site.github} target="_blank" rel="noreferrer">
          <GitHubIcon width={16} height={16} />
          <span>GitHub</span>
        </a>
        {onHome ? (
          <a className="chip-cta" href="#get">
            Get Nerve
          </a>
        ) : (
          <Link className="chip-cta" to="/#get">
            Get Nerve
          </Link>
        )}
      </div>
    </header>
  );
}
