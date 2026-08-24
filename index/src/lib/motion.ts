/**
 * The site's one easing curve. Mirrors `--ease` in `styles/global.css`; JS
 * motion props cannot read a CSS custom property, so this is its other half.
 */
export const EASE = [0.22, 1, 0.36, 1] as const;

/** A transition on the site's curve. */
export function ease(duration: number, delay = 0) {
  return { duration, delay, ease: EASE };
}
