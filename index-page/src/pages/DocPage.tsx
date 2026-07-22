import { Link, Navigate, useParams } from 'react-router-dom';
import { DocBlocks } from '../components/docs/DocBlocks';
import { docNav, getDocPage } from '../docs/content';

export function DocPage() {
  const { slug = '' } = useParams();
  const page = getDocPage(slug);

  if (!page) {
    return <Navigate to="/docs" replace />;
  }

  const idx = docNav.findIndex((d) => d.slug === page.slug);
  const prev = idx > 0 ? docNav[idx - 1] : null;
  const next = idx >= 0 && idx < docNav.length - 1 ? docNav[idx + 1] : null;

  return (
    <article className="doc-article">
      <header className="doc-hero">
        <p className="eyebrow">Docs</p>
        <h1 className="doc-title">{page.title}</h1>
        <p className="doc-lede">{page.lede}</p>
      </header>

      <DocBlocks blocks={page.blocks} />

      <nav className="doc-pager" aria-label="Adjacent docs">
        {prev ? (
          <Link to={`/docs/${prev.slug}`} className="doc-pager-link">
            <span>Previous</span>
            <strong>{prev.title}</strong>
          </Link>
        ) : (
          <span />
        )}
        {next ? (
          <Link to={`/docs/${next.slug}`} className="doc-pager-link doc-pager-link--next">
            <span>Next</span>
            <strong>{next.title}</strong>
          </Link>
        ) : (
          <span />
        )}
      </nav>
    </article>
  );
}
