import { motion } from 'motion/react';
import { LiveRibbon } from '../LiveRibbon';
import { useLocale } from '../../i18n/locale';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import { ease } from '../../lib/motion';
import { sectionTitle } from '../../lib/ui';

export function HubSignalStrip() {
  const { t } = useLocale();
  const reduced = usePrefersReducedMotion();

  return (
    <section
      className="bg-night bg-[radial-gradient(circle_at_82%_18%,rgb(66_92_164/22%),transparent_34rem)] px-[var(--page-gutter)] py-[clamp(92px,12vw,152px)] text-night-text"
      aria-labelledby="home-signal-title"
    >
      <div className="mx-auto grid w-full max-w-page grid-cols-[minmax(0,0.9fr)_minmax(380px,1.1fr)] items-center gap-[clamp(54px,9vw,116px)] max-lap:grid-cols-1 max-lap:gap-14">
        <motion.div
          className="max-w-[520px] max-lap:max-w-[680px]"
          initial={reduced ? false : { opacity: 0, y: 28 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-20%' }}
          transition={ease(0.7)}
        >
          <h2 id="home-signal-title" className={sectionTitle}>
            {t.hub.signal.title}
          </h2>
        </motion.div>

        <motion.div
          className="rounded-[22px] border border-white/10 bg-[color-mix(in_srgb,var(--color-night-raised)_88%,transparent)] p-[30px] max-sm:rounded-2xl max-sm:px-[18px] max-sm:py-[22px]"
          initial={reduced ? false : { opacity: 0, scaleX: 0.92 }}
          whileInView={{ opacity: 1, scaleX: 1 }}
          viewport={{ once: true, margin: '-10%' }}
          transition={ease(0.9)}
        >
          <LiveRibbon
            size="lg"
            load={1}
            showLabels
            tone="night"
            trackClassName="h-[18px] bg-night-raised shadow-[0_0_44px_rgb(0_122_255/24%)]"
          />
        </motion.div>
      </div>
    </section>
  );
}
