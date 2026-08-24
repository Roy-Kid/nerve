import { motion } from 'motion/react';
import { Link } from 'react-router-dom';
import { useLocale } from '../../i18n/locale';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import { cn } from '../../lib/utils';
import { ease } from '../../lib/motion';
import { homeLink, homeLinkChevron, sectionBody, sectionTitle } from '../../lib/ui';

export function HubDocsSection() {
  const { t } = useLocale();
  const reduced = usePrefersReducedMotion();

  return (
    <section
      className="bg-page bg-[radial-gradient(circle_at_50%_5%,--alpha(var(--color-blue)/8%),transparent_34%)] px-[var(--page-gutter)] pt-[clamp(94px,12vw,150px)] pb-[72px] text-center text-label"
      aria-labelledby="home-docs-title"
    >
      <motion.div
        className="mx-auto w-full max-w-[760px]"
        initial={reduced ? false : { opacity: 0, y: 28 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: '-20%' }}
        transition={ease(0.7)}
      >
        <h2 id="home-docs-title" className={sectionTitle}>
          {t.hub.docs.title}
        </h2>
        <p className={cn(sectionBody, 'mx-auto text-label-2')}>{t.hub.docs.body}</p>
        <div className="mt-[26px] flex justify-center">
          <Link to="/docs" className={homeLink}>
            {t.hub.docs.cta}
            <span aria-hidden="true" className={homeLinkChevron}>
              {' '}
              ›
            </span>
          </Link>
        </div>
      </motion.div>
    </section>
  );
}
