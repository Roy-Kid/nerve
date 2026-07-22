import { Link } from 'react-router-dom';
import { docNav } from '../docs/content';

export function DocsIndex() {
  return (
    <article className="doc-article">
      <header className="doc-hero">
        <p className="eyebrow">Documentation</p>
        <h1 className="doc-title">Everything that used to live in the repo README.</h1>
        <p className="doc-lede">
          Install the app, wire agent plugins, push snapshots, and understand how status
          paints the ribbon. Product surface stays on the home page; this is the handbook.
        </p>
      </header>

      <ul className="docs-cards">
        {docNav.map((item) => (
          <li key={item.slug}>
            <Link to={`/docs/${item.slug}`} className="docs-card">
              <strong>{item.title}</strong>
              <span>{item.summary}</span>
            </Link>
          </li>
        ))}
      </ul>
    </article>
  );
}
