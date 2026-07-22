import type { DocBlock } from '../../docs/content';

export function DocBlocks({ blocks }: { blocks: DocBlock[] }) {
  return (
    <div className="doc-blocks">
      {blocks.map((b, i) => {
        switch (b.type) {
          case 'h2':
            return (
              <h2 key={i} className="doc-h2">
                {b.text}
              </h2>
            );
          case 'h3':
            return (
              <h3 key={i} className="doc-h3">
                {b.text}
              </h3>
            );
          case 'p':
            return (
              <p key={i} className="doc-p">
                {b.text}
              </p>
            );
          case 'ul':
            return (
              <ul key={i} className="doc-list">
                {b.items.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            );
          case 'ol':
            return (
              <ol key={i} className="doc-list doc-list--ol">
                {b.items.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ol>
            );
          case 'code':
            return (
              <pre key={i} className="doc-code">
                <code data-lang={b.lang || 'text'}>{b.code}</code>
              </pre>
            );
          case 'table':
            return (
              <div key={i} className="doc-table-wrap">
                <table className="doc-table">
                  <thead>
                    <tr>
                      {b.headers.map((h) => (
                        <th key={h}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {b.rows.map((row, ri) => (
                      <tr key={ri}>
                        {row.map((cell, ci) => (
                          <td key={ci}>{cell}</td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            );
          case 'callout':
            return (
              <aside key={i} className="doc-callout">
                {b.title ? <strong>{b.title}</strong> : null}
                <p>{b.text}</p>
              </aside>
            );
          default:
            return null;
        }
      })}
    </div>
  );
}
