import type { DocBlock } from '../../docs/content';

const cell = 'border-b border-[rgb(52_75_114/8%)] px-[0.85rem] py-[0.7rem] text-left align-top';

export function DocBlocks({ blocks }: { blocks: DocBlock[] }) {
  return (
    <div className="flex flex-col gap-[0.85rem]">
      {blocks.map((b, i) => {
        switch (b.type) {
          case 'h2':
            return (
              <h2
                key={i}
                className="mt-[1.4rem] mb-[0.15rem] font-display text-[1.35rem] font-bold tracking-[-0.03em]"
              >
                {b.text}
              </h2>
            );
          case 'h3':
            return (
              <h3 key={i} className="mt-[0.9rem] mb-[0.1rem] text-[1.05rem] font-[650]">
                {b.text}
              </h3>
            );
          case 'p':
            return (
              <p key={i} className="m-0 text-[0.98rem] leading-[1.6] text-ink-dim">
                {b.text}
              </p>
            );
          case 'ul':
            return (
              <ul
                key={i}
                className="m-0 pl-[1.2rem] text-[0.96rem] leading-[1.55] text-ink-dim [&>li+li]:mt-[0.35rem]"
              >
                {b.items.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            );
          case 'ol':
            return (
              <ol
                key={i}
                className="m-0 pl-[1.2rem] text-[0.96rem] leading-[1.55] text-ink-dim [&>li+li]:mt-[0.35rem]"
              >
                {b.items.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ol>
            );
          case 'code':
            return (
              <pre
                key={i}
                className="my-[0.15rem] overflow-x-auto rounded-[0.95rem] border border-[rgb(56_79_116/10%)] bg-[#13203c] px-[1.1rem] py-4 font-mono text-[0.8rem] leading-[1.5] text-[#e8eefc]"
              >
                <code data-lang={b.lang || 'text'} className="font-[inherit] whitespace-pre">
                  {b.code}
                </code>
              </pre>
            );
          case 'table':
            return (
              <div
                key={i}
                className="overflow-x-auto rounded-2xl border border-[rgb(56_79_116/10%)] bg-white/78 shadow-card"
              >
                <table className="w-full border-collapse text-[0.88rem]">
                  <thead>
                    <tr>
                      {b.headers.map((h) => (
                        <th
                          key={h}
                          className={`${cell} bg-[rgb(77_134_247/5%)] text-[0.72rem] font-[650] tracking-[0.04em] text-ink-faint uppercase`}
                        >
                          {h}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody className="[&>tr:last-child>td]:border-b-0">
                    {b.rows.map((row, ri) => (
                      <tr key={ri}>
                        {row.map((c, ci) => (
                          <td key={ci} className={`${cell} text-ink-dim`}>
                            {c}
                          </td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            );
          case 'callout':
            return (
              <aside
                key={i}
                className="my-[0.2rem] rounded-2xl border border-[rgb(77_134_247/18%)] bg-[linear-gradient(135deg,rgb(77_134_247/8%),rgb(255_255_255/70%))] px-[1.05rem] py-[0.95rem]"
              >
                {b.title ? (
                  <strong className="mb-1 block text-[0.92rem]">{b.title}</strong>
                ) : null}
                <p className="m-0 text-[0.92rem] leading-[1.5] text-ink-dim">{b.text}</p>
              </aside>
            );
          default:
            return null;
        }
      })}
    </div>
  );
}
