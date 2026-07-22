import { useEffect, useRef, useState, type RefObject } from 'react';
import { truths } from '../config';
import { LiveRibbon } from './LiveRibbon';

function useInView(threshold = 0.35) {
  const ref = useRef<HTMLElement | null>(null);
  const [on, setOn] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) setOn(true);
      },
      { threshold },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [threshold]);

  return { ref, on };
}

export function Story() {
  const { ref, on } = useInView(0.2);

  return (
    <section
      className={`story${on ? ' is-in' : ''}`}
      id="story"
      ref={ref as RefObject<HTMLElement>}
      aria-labelledby="story-title"
    >
      <div className="story-rail" aria-hidden="true">
        <LiveRibbon size="md" alive load={on ? 1 : 0.4} />
      </div>

      <div className="story-wrap">
        <header className="story-head">
          <p className="eyebrow">How it feels</p>
          <h2 id="story-title" className="display display--sm">
            One continuous signal.
            <br />
            <em>Nothing else on screen.</em>
          </h2>
        </header>

        <ol className="truth-list">
          {truths.map((t, i) => (
            <li
              key={t.kicker}
              className="truth"
              style={{ transitionDelay: `${120 + i * 90}ms` }}
            >
              <span className="truth-kicker">{t.kicker}</span>
              <h3>{t.title}</h3>
              <p>{t.body}</p>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}
