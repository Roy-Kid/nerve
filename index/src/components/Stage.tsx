import { Link } from 'react-router-dom';
import { site } from '../config';
import { MacDevicePreview } from './MacDevicePreview';
import { motion } from 'motion/react';
import { usePrefersReducedMotion } from '../hooks/usePrefersReducedMotion';
import { ease } from '../lib/motion';
import { useLocale } from '../i18n/locale';
import { productCta, productCtaRow } from '../lib/ui';

export function Stage() {
  const reduced = usePrefersReducedMotion();
  const { t } = useLocale();

  return (
    <section
      className="flex min-h-svh flex-col items-center overflow-hidden px-[var(--page-gutter)] pt-22 text-center max-md:pt-[4.75rem]"
      id="top"
      aria-labelledby="hero-title"
    >
      <div className="relative z-2 mx-auto w-[min(100%,46rem)]">
        <motion.h1
          id="hero-title"
          className="m-0 font-display text-[clamp(2.75rem,7.5vw,5.25rem)] leading-[1.02] font-semibold tracking-[-0.04em]"
          initial={reduced ? false : { opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.05 }}
        >
          <span className="block">{t.macos.headline[0]}</span>
          <span className="block text-label-2">{t.macos.headline[1]}</span>
        </motion.h1>

        <motion.p
          className="mx-auto mt-[1.1rem] max-w-[34rem] text-[clamp(1.05rem,2.2vw,1.35rem)] leading-[1.45] text-label-2"
          initial={reduced ? false : { opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.1 }}
        >
          {t.macos.subhead}
        </motion.p>

        <motion.div
          className={productCtaRow}
          initial={reduced ? false : { opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.15 }}
        >
          <Link to="/docs/get-started" className={productCta}>
            {t.macos.openDocs}
          </Link>
          <a className={productCta} href={site.github} target="_blank" rel="noreferrer">
            GitHub
          </a>
        </motion.div>
      </div>

      <motion.div
        className="relative z-1 mt-[clamp(2rem,6vw,3.5rem)] w-[min(100%,var(--container-page))] origin-bottom motion-reduce:!transform-none"
        initial={reduced ? false : { opacity: 0, y: 64, scale: 0.94 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={ease(0.9, 0.12)}
        aria-label={t.macos.ribbonPreviewLabel}
      >
        <MacDevicePreview variant="hero" />
      </motion.div>
    </section>
  );
}
