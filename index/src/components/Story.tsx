import { useEffect, useRef, useState, type RefObject } from 'react';
import { LiveRibbon } from './LiveRibbon';
import { useLocale } from '../i18n/locale';
import { productSectionTitle } from '../lib/ui';

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
  const { t } = useLocale();

  return (
    <section
      className="relative overflow-hidden bg-night bg-[radial-gradient(circle_at_14%_0%,rgb(62_92_164/18%),transparent_36rem)] px-[var(--page-gutter)] py-[clamp(4rem,10vw,7rem)] text-night-text"
      id="story"
      ref={ref as RefObject<HTMLElement>}
      aria-labelledby="story-title"
    >
      <div className="relative z-5 mx-auto mb-10 w-[min(100%,var(--container-page))]" aria-hidden="true">
        <LiveRibbon
          size="md"
          alive
          load={on ? 1 : 0.4}
          trackClassName="shadow-[0_0_0_5px_rgb(255_255_255/45%),0_12px_30px_rgb(55_79_123/12%)]"
        />
      </div>

      <div className="mx-auto w-[min(100%,var(--container-page))]">
        <header className="mb-[3.3rem] max-w-[30rem]">
          <h2 id="story-title" className={`${productSectionTitle} text-night-text`}>
            {t.macos.storyTitle}
          </h2>
        </header>

        <ol className="m-0 grid list-none grid-cols-3 gap-6 p-0 max-wide:grid-cols-1">
          {t.macos.truths.map((truth) => (
            <li key={truth.title} className="flex flex-col">
              <h3 className="m-0 mb-2 font-display text-[1.35rem] leading-[1.18] font-semibold tracking-[-0.035em] text-night-text">
                {truth.title}
              </h3>
              <p className="m-0 text-[0.96rem] text-night-muted">{truth.body}</p>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}
