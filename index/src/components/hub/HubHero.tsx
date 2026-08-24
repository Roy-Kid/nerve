import { motion } from 'motion/react';
import { LiveRibbon } from '../LiveRibbon';
import { useLocale } from '../../i18n/locale';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import { ease } from '../../lib/motion';

export function HubHero() {
  const { t } = useLocale();
  const reduced = usePrefersReducedMotion();

  return (
    <section
      className="relative flex h-svh flex-col overflow-hidden bg-page bg-[radial-gradient(circle_at_50%_78%,--alpha(var(--color-blue)/7%),transparent_30%)] px-[var(--page-gutter)] pt-12 text-label"
      aria-labelledby="home-hero-title"
    >
      <div className="relative z-2 mx-auto flex w-[min(100%,980px)] flex-1 flex-col items-center justify-center pb-[clamp(28px,5vh,54px)] text-center">
        <motion.img
          src={`${import.meta.env.BASE_URL}logo.png`}
          alt=""
          width={72}
          height={72}
          className="mx-auto mb-4 h-auto w-[clamp(50px,5vw,66px)] rounded-[16px] drop-shadow-[0_14px_34px_rgb(30_56_105/16%)]"
          initial={reduced ? false : { opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={ease(0.6)}
        />

        <motion.p
          className="mt-0 mb-[clamp(22px,3vh,32px)] font-mono text-[clamp(10px,0.9vw,12px)] leading-[1.45] font-[500] tracking-[0.11em] text-label-2 uppercase"
          initial={reduced ? false : { opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={ease(0.6, 0.03)}
        >
          {t.hub.kicker}
        </motion.p>

        <motion.h1
          id="home-hero-title"
          className="m-0 font-display text-[clamp(82px,11vw,150px)] leading-[0.84] font-[720] tracking-[-0.078em] text-label max-sm:text-[clamp(72px,22vw,94px)]"
          initial={reduced ? false : { opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          transition={ease(0.7, 0.05)}
        >
          {t.hub.brand}
        </motion.h1>

        <motion.p
          className="mt-[clamp(26px,3.5vh,38px)] mb-0 max-w-[860px] text-balance text-[clamp(20px,2.35vw,30px)] leading-[1.28] font-[450] tracking-[-0.032em] text-label-2 max-sm:max-w-[24ch] max-sm:text-[19px]"
          initial={reduced ? false : { opacity: 0, y: 18 }}
          animate={{ opacity: 1, y: 0 }}
          transition={ease(0.7, 0.12)}
        >
          {t.hub.tagline}
        </motion.p>
      </div>

      <motion.div
        className="relative z-1 mx-auto w-full max-w-[1120px] origin-center pb-[clamp(72px,12vh,126px)]"
        initial={reduced ? false : { opacity: 0, scaleX: 0.82 }}
        animate={{ opacity: 1, scaleX: 1 }}
        transition={ease(1.1, 0.18)}
      >
        <LiveRibbon
          size="lg"
          load={1}
          trackClassName="h-3.5 shadow-[0_0_34px_rgb(0_122_255/24%),0_0_0_1px_rgb(0_0_0/5%)] max-sm:h-2.5"
        />
      </motion.div>
    </section>
  );
}
