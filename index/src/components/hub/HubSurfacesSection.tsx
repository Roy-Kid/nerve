import { motion } from 'motion/react';
import { Link } from 'react-router-dom';
import { getTmuxGuidePath } from '../../config';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import { useLocale } from '../../i18n/locale';
import { cn } from '../../lib/utils';
import { ease } from '../../lib/motion';
import { homeLink, homeLinkChevron, sectionTitle } from '../../lib/ui';

export function HubSurfacesSection() {
  const { locale, t } = useLocale();
  const tmuxGuidePath = getTmuxGuidePath(locale);
  const reduced = usePrefersReducedMotion();

  return (
    <section
      className="bg-white px-[var(--page-gutter)] py-[clamp(96px,13vw,168px)] text-label"
      aria-labelledby="home-surfaces-title"
    >
      <motion.header
        className="mx-auto w-full max-w-[780px] text-center"
        initial={reduced ? false : { opacity: 0, y: 24 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: '-15%' }}
        transition={ease(0.65)}
      >
        <h2 id="home-surfaces-title" className={sectionTitle}>
          {t.hub.surfaces.title}
        </h2>
      </motion.header>

      <div className="mx-auto mt-[clamp(64px,8vw,92px)] grid w-full max-w-page grid-cols-2 border-y border-black/10 max-sm:mt-[52px] max-sm:grid-cols-1">
        {[t.hub.macos, t.hub.tmux].map((surface, index) => (
          <motion.article
            key={surface.kicker}
            className={cn(
              'flex min-w-0 flex-col items-start p-[clamp(42px,5vw,68px)] max-sm:px-1 max-sm:py-[42px]',
              index > 0 && 'border-l border-black/10 max-sm:border-t max-sm:border-l-0',
            )}
            initial={reduced ? false : { opacity: 0, y: 24 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, margin: '-10%' }}
            transition={ease(0.65, reduced ? 0 : index * 0.08)}
          >
            <p className="m-0 mb-7 text-sm/[1.55] font-[650] text-blue-pressed max-sm:mb-5">
              {surface.kicker}
            </p>
            <h3 className="m-0 text-[clamp(30px,3vw,42px)] leading-[1.05] font-[620] tracking-[-0.045em]">
              {surface.title}
            </h3>
            <p className="mt-4 mb-7 text-[17px] leading-[1.55] text-label-2">{surface.body}</p>
            <Link
              to={index === 0 ? '/macos' : tmuxGuidePath}
              className={cn(homeLink, 'mt-auto')}
            >
              {surface.cta}
              <span aria-hidden="true" className={homeLinkChevron}>
                {' '}
                ›
              </span>
            </Link>
          </motion.article>
        ))}
      </div>
    </section>
  );
}
