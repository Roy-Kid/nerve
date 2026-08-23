import { useEffect } from 'react';
import { motion } from 'motion/react';
import { Link, Navigate, useParams } from 'react-router-dom';
import { Footer } from '../components/Footer';
import { Nav } from '../components/Nav';
import { ProductShell } from '../components/ProductShell';
import { TmuxSidebarPreview } from '../components/TmuxSidebarPreview';
import { getTmuxGuide } from '../docs/tmux-guide';
import { usePrefersReducedMotion } from '../hooks/usePrefersReducedMotion';
import { useLocale } from '../i18n/locale';
import { ease } from '../lib/motion';
import { cn } from '../lib/utils';
import { homeLink, homeLinkChevron } from '../lib/ui';
import { getTmuxGuidePath } from '../config';

/** Band heading shared by the priority and closing sections. */
const bandTitle =
  'm-0 font-display text-[clamp(40px,5.3vw,68px)] leading-[1.02] font-[620] ' +
  'tracking-[-0.052em] text-balance max-sm:text-[clamp(37px,11vw,48px)] max-sm:leading-[1.04]';

const bandPadding = 'px-[var(--page-gutter)] py-[clamp(92px,12vw,152px)] max-sm:py-[92px]';

const sectionInner = 'mx-auto w-[min(100%,var(--container-page))]';

/** The dot beside a priority label — the same three hues the surfaces paint. */
const toneDot: Record<string, string> = {
  running: 'bg-[#58a6ff]',
  attention: 'bg-[#ffbd45]',
  problem: 'bg-[#ff5f57]',
};

export function TmuxGuidePage() {
  const { lang = 'zh' } = useParams();
  const guide = getTmuxGuide(lang);
  const reduced = usePrefersReducedMotion();
  const { locale, setLocale } = useLocale();

  useEffect(() => {
    if (guide && locale !== guide.lang) setLocale(guide.lang);
  }, [guide, locale, setLocale]);

  if (!guide) {
    return <Navigate to={getTmuxGuidePath(locale)} replace />;
  }

  return (
    <ProductShell>
      <Nav variant="tmux" />
      <main className="bg-page">
        <section
          className="min-h-svh overflow-hidden bg-page bg-[radial-gradient(circle_at_50%_82%,--alpha(var(--color-blue)/9%),transparent_36%)] px-[var(--page-gutter)] pt-[clamp(112px,14vw,164px)] pb-[clamp(72px,9vw,116px)] text-label max-sm:min-h-auto max-sm:pt-[104px] max-sm:pb-[76px]"
          aria-labelledby="tmux-title"
        >
          <div className="mx-auto w-[min(100%,940px)] text-center">
            <motion.h1
              id="tmux-title"
              className="m-0 font-display text-[clamp(56px,8.3vw,106px)] leading-[0.94] font-[690] tracking-[-0.068em] text-balance max-sm:text-[clamp(48px,15vw,68px)] max-sm:leading-[0.98]"
              initial={reduced ? false : { opacity: 0, y: 24 }}
              animate={{ opacity: 1, y: 0 }}
              transition={ease(0.72, 0.05)}
            >
              <span className="block">{guide.title[0]}</span>
              <span className="mt-[0.09em] block text-label-2">{guide.title[1]}</span>
            </motion.h1>
            <motion.p
              className="mx-auto mt-7 max-w-[640px] text-[clamp(18px,2vw,22px)] leading-[1.5] tracking-[-0.02em] text-balance text-label-2 max-sm:mt-[22px] max-sm:text-[17px]"
              initial={reduced ? false : { opacity: 0, y: 18 }}
              animate={{ opacity: 1, y: 0 }}
              transition={ease(0.68, 0.12)}
            >
              {guide.lede}
            </motion.p>
            <motion.div
              className="mt-7 flex flex-wrap justify-center gap-x-[30px] gap-y-3 max-sm:mt-6 max-sm:gap-x-6 max-sm:gap-y-2.5"
              initial={reduced ? false : { opacity: 0, y: 14 }}
              animate={{ opacity: 1, y: 0 }}
              transition={ease(0.65, 0.18)}
            >
              <Link to="/docs/tmux" className={homeLink}>
                {guide.docsCta}
                <span aria-hidden="true" className={homeLinkChevron}>
                  {' '}
                  ›
                </span>
              </Link>
            </motion.div>
          </div>

          <motion.div
            className="mx-auto mt-[clamp(58px,7vw,88px)] w-[min(100%,var(--container-page))] max-sm:mt-[52px]"
            initial={reduced ? false : { opacity: 0, y: 56, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            transition={ease(0.95, 0.15)}
          >
            <TmuxSidebarPreview variant="hero" />
          </motion.div>
        </section>

        <section
          className={cn(
            bandPadding,
            'bg-night bg-[radial-gradient(circle_at_82%_12%,rgb(66_92_164/24%),transparent_34rem)] text-night-text',
          )}
          aria-labelledby="tmux-priority-title"
        >
          <div className={sectionInner}>
            <motion.header
              className="max-w-[760px]"
              initial={reduced ? false : { opacity: 0, y: 28 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: '-18%' }}
              transition={ease(0.7)}
            >
              <h2 id="tmux-priority-title" className={bandTitle}>
                {guide.priority.title}
              </h2>
            </motion.header>

            <div className="mt-[clamp(58px,8vw,88px)] grid grid-cols-3 border-y border-white/12 max-lap:grid-cols-1 max-sm:mt-[52px]">
              {guide.priority.items.map((item, index) => (
                <motion.article
                  key={item.tone}
                  className={cn(
                    'min-w-0 px-[clamp(24px,4vw,48px)] pt-[42px] pb-[46px] max-sm:px-1 max-sm:pt-9 max-sm:pb-10',
                    index > 0 && 'border-l border-white/12 max-lap:border-t max-lap:border-l-0',
                  )}
                  initial={reduced ? false : { opacity: 0, y: 26 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true, margin: '-12%' }}
                  transition={ease(0.62, index * 0.07)}
                >
                  <p className="m-0 mb-[34px] flex items-center gap-[9px] text-[13px] font-semibold text-night-muted max-sm:mb-6">
                    <i
                      aria-hidden="true"
                      className={cn('size-2 rounded-full', toneDot[item.tone])}
                    />
                    {item.label}
                  </p>
                  <h3 className="m-0 text-[clamp(25px,2.7vw,34px)] leading-[1.08] font-semibold tracking-[-0.04em] text-night-text">
                    {item.title}
                  </h3>
                </motion.article>
              ))}
            </div>
          </div>
        </section>

        <section
          className={cn(
            bandPadding,
            'bg-night bg-[radial-gradient(circle_at_50%_0%,--alpha(var(--color-blue)/12%),transparent_34rem)] text-center text-night-text',
          )}
          aria-labelledby="tmux-closing-title"
        >
          <div className={cn(sectionInner, 'max-w-[830px]')}>
            <h2 id="tmux-closing-title" className={bandTitle}>
              {guide.closing.title}
            </h2>
            <Link to="/docs/tmux" className={cn(homeLink, 'mt-7 text-[#58a6ff]')}>
              {guide.closing.cta}
              <span aria-hidden="true" className={homeLinkChevron}>
                {' '}
                ›
              </span>
            </Link>
          </div>
        </section>
      </main>
      <Footer />
    </ProductShell>
  );
}
