import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { sources } from '../config';

export function Sources() {
  const ref = useRef<HTMLElement | null>(null);
  const [on, setOn] = useState(false);
  const [active, setActive] = useState(0);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      ([e]) => {
        if (e.isIntersecting) setOn(true);
      },
      { threshold: 0.25 },
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);

  useEffect(() => {
    if (!on) return;
    const id = window.setInterval(() => {
      setActive((i) => (i + 1) % sources.length);
    }, 2400);
    return () => window.clearInterval(id);
  }, [on]);

  return (
    <section
      className={`sources${on ? ' is-in' : ''}`}
      id="sources"
      ref={ref}
      aria-labelledby="sources-title"
    >
      <div className="sources-wrap">
        <div className="sources-copy">
          <p className="eyebrow">Sources</p>
          <h2 id="sources-title" className="display display--sm">
            Agents report in.
            <br />
            <span className="soft">You stay in the bar.</span>
          </h2>
          <p className="lede lede--tight">
            One marketplace plugin covers Claude Code, Codex, and Grok. Hooks are
            fail-open and stateless — if Nerve is down, agents keep working.
          </p>
        </div>

        <div className="constellation" aria-hidden={!on}>
          <div className="constellation-core">
            <img
              src={`${import.meta.env.BASE_URL}logo.png`}
              alt=""
              width={72}
              height={72}
            />
            <span>Nerve</span>
          </div>

          <svg className="constellation-links" viewBox="0 0 400 320" aria-hidden="true">
            {sources.map((_, i) => {
              const angle = (-90 + i * 90) * (Math.PI / 180);
              const x = 200 + Math.cos(angle) * 130;
              const y = 160 + Math.sin(angle) * 100;
              return (
                <g key={i}>
                  <line
                    className={`c-line${active === i ? ' is-hot' : ''}`}
                    x1="200"
                    y1="160"
                    x2={x}
                    y2={y}
                  />
                  <circle
                    className={`c-packet${active === i ? ' is-hot' : ''}`}
                    r="3.5"
                    style={
                      {
                        ['--x1' as string]: '200',
                        ['--y1' as string]: '160',
                        ['--x2' as string]: String(x),
                        ['--y2' as string]: String(y),
                      } as CSSProperties
                    }
                  >
                    <animateMotion
                      dur="2.4s"
                      begin={`${i * 0.6}s`}
                      repeatCount="indefinite"
                      path={`M200,160 L${x},${y}`}
                    />
                  </circle>
                </g>
              );
            })}
          </svg>

          <ul className="constellation-nodes">
            {sources.map((s, i) => (
              <li
                key={s.name}
                className={`c-node c-node--${i}${active === i ? ' is-hot' : ''}`}
                onMouseEnter={() => setActive(i)}
              >
                <strong>{s.name}</strong>
                <span>{s.how}</span>
              </li>
            ))}
          </ul>
        </div>
      </div>

      <div className="ingest-strip">
        <code>
          POST <em>http://127.0.0.1:17890</em>/v1/snapshot
        </code>
        <span>Loopback only · any producer that can HTTP</span>
      </div>
    </section>
  );
}
