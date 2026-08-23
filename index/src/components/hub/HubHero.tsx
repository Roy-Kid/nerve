import { motion } from 'motion/react';
import { Link } from 'react-router-dom';
import { MacDevicePreview } from '../MacDevicePreview';
import { TmuxSidebarPreview } from '../TmuxSidebarPreview';
import { LiveRibbon } from '../LiveRibbon';
import { getTmuxGuidePath } from '../../config';
import { useLocale } from '../../i18n/locale';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import { ease } from '../../lib/motion';
import { homeLink, homeLinkChevron } from '../../lib/ui';

export function HubHero() {
  const { locale, t } = useLocale();
  const tmuxGuidePath = getTmuxGuidePath(locale);
  const reduced = usePrefersReducedMotion();

  return (
    <section
      className={[
        'relative min-h-svh overflow-hidden px-[var(--page-gutter)] pt-[clamp(116px,15vw,170px)] pb-0 text-label',
        'max-sm:min-h-auto max-sm:pt-[104px]',
        'bg-[radial-gradient(circle_at_50%_92%,--alpha(var(--color-blue)/8%),transparent_32%)] bg-page',
      ].join(' ')}
      aria-labelledby="home-hero-title"
    >
      <div className="relative z-2 mx-auto w-[min(100%,920px)] text-center">
        <motion.img
          src={`${import.meta.env.BASE_URL}logo.png`}
          alt=""
          width={72}
          height={72}
          className="mx-auto mb-5 h-auto w-[clamp(58px,6vw,76px)] rounded-[18px] drop-shadow-[0_12px_28px_rgb(30_56_105/14%)]"
          initial={reduced ? false : { opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={ease(0.6)}
        />

        <motion.h1
          id="home-hero-title"
          className="m-0 font-display text-balance max-sm:leading-none"
          initial={reduced ? false : { opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          transition={ease(0.7, 0.05)}
        >
          <span className="block text-[clamp(70px,9.5vw,132px)] leading-[0.82] font-[720] tracking-[-0.072em] text-label max-sm:text-[clamp(70px,22vw,92px)]">
            {t.hub.brand}
          </span>
          <span className="mx-auto mt-[30px] block max-w-[780px] text-[clamp(36px,4.6vw,64px)] leading-[1.02] font-[620] tracking-[-0.052em] text-label max-sm:mt-6 max-sm:text-[clamp(35px,10.5vw,44px)]">
            {t.hub.tagline}
          </span>
        </motion.h1>


        <motion.div
          className="mt-[30px] flex flex-wrap items-center justify-center gap-x-[30px] gap-y-3 max-sm:mt-[22px] max-sm:gap-x-6 max-sm:gap-y-2.5"
          initial={reduced ? false : { opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={ease(0.7, 0.2)}
        >
          <Link to="/macos" className={homeLink}>
            {t.hub.heroCtaMacos}
            <span aria-hidden="true" className={homeLinkChevron}>
              {' '}
              ›
            </span>
          </Link>
          <Link to={tmuxGuidePath} className={homeLink}>
            {t.hub.heroCtaTmux}
            <span aria-hidden="true" className={homeLinkChevron}>
              {' '}
              ›
            </span>
          </Link>
        </motion.div>
      </div>

      <motion.div
        className="relative z-1 mx-auto mt-[clamp(58px,7vw,92px)] w-[min(100%,var(--container-page))] origin-bottom pb-[62px] max-sm:mt-[54px] max-sm:w-full max-sm:pb-[50px]"
        initial={reduced ? false : { opacity: 0, y: 56, scale: 0.96 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={ease(1, 0.15)}
      >
        <div className="relative z-0 mx-auto mb-8 w-[min(84%,860px)] max-lap:mb-[26px] max-lap:w-[92%] max-sm:mb-7 max-sm:w-[calc(100%-12px)]">
          <LiveRibbon
            size="lg"
            load={1}
            trackClassName="h-3 shadow-[0_0_28px_rgb(0_122_255/23%),0_0_0_1px_rgb(0_0_0/5%)]"
          />
        </div>
        <div className="relative z-1 grid grid-cols-2 items-start gap-[clamp(20px,3vw,38px)] max-lap:grid-cols-1 max-lap:gap-[50px]">
          <article className="min-w-0">
            <header className="mx-1 mb-3 flex items-baseline justify-start gap-4 text-xs/[1.55] text-label-3 max-sm:mx-0.5">
              <strong className="text-[13px] font-[650] text-label">macOS</strong>
            </header>
            <MacDevicePreview variant="card" />
          </article>
          <article className="min-w-0">
            <header className="mx-1 mb-3 flex items-baseline justify-start gap-4 text-xs/[1.55] text-label-3 max-sm:mx-0.5">
              <strong className="text-[13px] font-[650] text-label">tmux</strong>
            </header>
            <TmuxSidebarPreview variant="card" />
          </article>
        </div>
      </motion.div>
    </section>
  );
}
