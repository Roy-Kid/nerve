import type { ReactNode } from 'react';
import { motion } from 'motion/react';
import { Link } from 'react-router-dom';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import { cn } from '../../lib/utils';
import { ease } from '../../lib/motion';
import { homeLink, homeLinkChevron, sectionBody, sectionTitle } from '../../lib/ui';

type HubSurfaceSectionProps = {
  id: string;
  kicker: string;
  title: readonly [string, string];
  lede: string;
  cta: string;
  ctaTo: string;
  children: ReactNode;
  points?: readonly { title: string; body?: string }[];
  /** Same type and preview size; only the side changes. */
  layout?: 'start' | 'end';
  /** Gives dense desktop surfaces more room without changing the shared 16:10 frame. */
  visualSize?: 'standard' | 'large';
  /** Apple paper: page gray vs white. */
  ground?: 'page' | 'white';
};

const pad =
  'scroll-mt-12 flex h-svh flex-col justify-center overflow-hidden px-[var(--page-gutter)] py-[clamp(58px,8vh,92px)] max-sm:py-11';

export function HubSurfaceSection({
  id,
  kicker,
  title,
  lede,
  cta,
  ctaTo,
  children,
  points,
  layout = 'start',
  visualSize = 'standard',
  ground = 'page',
}: HubSurfaceSectionProps) {
  const reduced = usePrefersReducedMotion();
  const flipped = layout === 'end';

  const copy = (
    <motion.header
      className="max-w-[520px]"
      initial={reduced ? false : { opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-15%' }}
      transition={ease(0.65)}
    >
      <p className="m-0 mb-5 text-sm/[1.55] font-[650] text-blue-pressed">{kicker}</p>
      <h2 id={`${id}-title`} className={sectionTitle}>
        <span className="block">{title[0]}</span>
        <span className="mt-[0.08em] block text-label-2">{title[1]}</span>
      </h2>
      <p className={cn(sectionBody, 'text-label-2')}>{lede}</p>

      {points && points.length > 0 ? (
        <dl className="mt-[clamp(22px,3.5vh,34px)] border-t border-black/10">
          {points.map((point) => (
            <div
              key={point.title}
              className="grid grid-cols-[minmax(120px,0.62fr)_minmax(0,1fr)] gap-5 border-b border-black/8 py-3 max-sm:grid-cols-1 max-sm:gap-0.5 max-sm:py-2"
            >
              <dt className="text-[14px] font-[650] text-label">{point.title}</dt>
              {point.body ? (
                <dd className="m-0 text-[13px] leading-[1.42] text-label-2 max-sm:hidden">
                  {point.body}
                </dd>
              ) : null}
            </div>
          ))}
        </dl>
      ) : null}

      <div className="mt-6">
        <Link to={ctaTo} className={homeLink}>
          {cta}
          <span aria-hidden="true" className={homeLinkChevron}>
            {' '}
            ›
          </span>
        </Link>
      </div>
    </motion.header>
  );

  const shot = (
    <motion.div
      className={cn(
        'mx-auto flex aspect-[16/10] w-full min-w-0 items-center justify-center [&>*]:w-full [&_.mac-device--hero]:!w-[96%]',
        visualSize === 'large' ? 'max-w-[980px]' : 'max-w-[900px]',
      )}
      data-surface-preview
      data-surface-size={visualSize}
      initial={reduced ? false : { opacity: 0, y: 40, scale: 0.97 }}
      whileInView={{ opacity: 1, y: 0, scale: 1 }}
      viewport={{ once: true, margin: '-10%' }}
      transition={ease(0.9)}
    >
      {children}
    </motion.div>
  );

  return (
    <section
      id={id}
      className={cn(pad, ground === 'white' ? 'bg-white text-label' : 'bg-page text-label')}
      aria-labelledby={`${id}-title`}
    >
      <div
        className={cn(
          'mx-auto grid w-full max-w-[1280px] items-center max-lap:grid-cols-2 max-lap:gap-8 max-sm:grid-cols-1 max-sm:gap-[clamp(18px,3vh,28px)]',
          visualSize === 'large'
            ? 'gap-[clamp(30px,3vw,44px)]'
            : 'gap-[clamp(32px,4vw,60px)]',
          flipped
            ? 'grid-cols-[minmax(0,1.48fr)_minmax(280px,0.52fr)]'
            : 'grid-cols-[minmax(310px,0.52fr)_minmax(0,1.48fr)]',
        )}
      >
        <div className={cn(flipped && 'max-lap:order-1 lap:order-2')}>{copy}</div>
        <div className={cn(flipped && 'max-lap:order-2 lap:order-1')}>{shot}</div>
      </div>
    </section>
  );
}
