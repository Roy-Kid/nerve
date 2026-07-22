import { useEffect, useRef, useState } from 'react';
import { designNotes, lifecycle, statusMeta } from '../config';

export function Signal() {
  const ref = useRef<HTMLElement | null>(null);
  const [on, setOn] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      ([e]) => {
        if (e.isIntersecting) setOn(true);
      },
      { threshold: 0.2 },
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);

  return (
    <section
      className={`signal${on ? ' is-in' : ''}`}
      id="signal"
      ref={ref}
      aria-labelledby="signal-title"
    >
      <div className="signal-wrap">
        <header className="signal-head">
          <p className="eyebrow">Signal</p>
          <h2 id="signal-title" className="display display--sm">
            One session.
            <br />
            <span className="soft">One clear status.</span>
          </h2>
          <p className="lede lede--tight">
            Plugins push a single job per conversation. Subagents and background
            work only change that row’s facet — they never spawn noise in the panel.
          </p>
        </header>

        <ol className="life-track" aria-label="Session lifecycle">
          {lifecycle.map((step, i) => {
            const color = statusMeta[step.ribbon].color;
            return (
              <li
                key={step.phase}
                className="life-step"
                style={{ transitionDelay: `${100 + i * 70}ms` }}
              >
                <span className="life-dot" style={{ background: color }} aria-hidden="true" />
                <div className="life-copy">
                  <div className="life-meta">
                    <strong>{step.phase}</strong>
                    <code>{step.facet}</code>
                    <em style={{ color }}>{statusMeta[step.ribbon].label}</em>
                  </div>
                  <p>{step.note}</p>
                </div>
              </li>
            );
          })}
        </ol>

        <ul className="design-grid">
          {designNotes.map((n, i) => (
            <li
              key={n.title}
              className="design-card"
              style={{ transitionDelay: `${180 + i * 60}ms` }}
            >
              <h3>{n.title}</h3>
              <p>{n.body}</p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
