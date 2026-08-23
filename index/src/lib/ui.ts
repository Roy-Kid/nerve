/** Class recipes shared by more than one component.
 *
 * Only patterns that genuinely repeat live here — a "link that leans forward",
 * a section shell. Anything used once belongs in the component that uses it.
 */

/** Text link with a chevron that leans forward on hover. */
export const homeLink =
  'group inline-flex w-fit items-baseline text-[17px] font-[450] text-blue-pressed ' +
  'hover:underline hover:underline-offset-4 max-sm:text-[16px] ' +
  'focus-visible:rounded focus-visible:outline-[3px] focus-visible:outline-offset-4 ' +
  'focus-visible:outline-blue/30';

/** The chevron inside a [`homeLink`]. */
export const homeLinkChevron =
  'ml-[3px] transition-transform duration-150 group-hover:translate-x-[2px] motion-reduce:transition-none';

/** Section heading shared by the signal / surfaces / docs bands. */
export const sectionTitle =
  'm-0 font-display text-[clamp(40px,5.3vw,68px)] leading-[1.02] font-[620] ' +
  'tracking-[-0.052em] text-balance max-sm:text-[clamp(37px,11vw,48px)] max-sm:leading-[1.04]';

/** Body copy under a [`sectionTitle`]. Colour is the caller's — the band it
 *  sits in decides whether it is on paper or on night. */
export const sectionBody =
  'mt-[22px] max-w-[620px] text-[clamp(17px,2vw,21px)] leading-[1.52] ' +
  'tracking-[-0.018em] text-pretty max-sm:mt-[18px] max-sm:text-[17px]';

/** Small uppercase pill above a docs title. */
export const eyebrow =
  'mb-[1.05rem] inline-flex items-center gap-[0.58rem] rounded-full border ' +
  'border-[rgb(77_134_247/13%)] bg-white/60 px-[0.72rem] py-[0.42rem] font-mono ' +
  'text-[0.68rem] font-medium tracking-[0.11em] text-[#63728e] uppercase ' +
  'shadow-[0_7px_22px_rgb(79_99_135/5%)] backdrop-blur-[10px]';

/** Docs page header: eyebrow, title, lede. */
export const docTitle =
  'mt-[0.35rem] mb-[0.7rem] font-display text-[clamp(2rem,4vw,2.75rem)] ' +
  'leading-[1.08] font-[750] tracking-[-0.045em]';

export const docLede = 'm-0 max-w-[40rem] text-[1.05rem] leading-[1.55] text-ink-dim';

/** Section heading on the product pages (macOS / tmux). */
export const productSectionTitle =
  'm-0 font-display text-[clamp(2.1rem,5vw,3.5rem)] leading-[1.06] font-semibold tracking-[-0.035em]';

/** Quiet blue text link used for the product pages' calls to action. */
export const productCta =
  'focus-ring text-[17px] font-normal text-[#2997ff] transition-opacity duration-150 ' +
  'hover:underline hover:underline-offset-[0.2em] motion-reduce:transition-none';

/** The row a pair of [`productCta`] links sits in. */
export const productCtaRow = 'mt-[1.35rem] flex flex-wrap justify-center gap-x-7 gap-y-5';
