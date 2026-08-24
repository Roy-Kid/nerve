type SurfaceScreenshotProps = {
  src: string;
  alt: string;
  width: number;
  height: number;
  fit?: 'cover' | 'contain';
};

/** A captured product surface. The pixels come from the real app, not a CSS mock. */
export function SurfaceScreenshot({
  src,
  alt,
  width,
  height,
  fit = 'cover',
}: SurfaceScreenshotProps) {
  return (
    <img
      src={`${import.meta.env.BASE_URL}${src}`}
      alt={alt}
      width={width}
      height={height}
      loading="lazy"
      decoding="async"
      className={`block aspect-[16/10] w-full rounded-[18px] border border-black/20 bg-[#191a1b] shadow-[0_34px_76px_rgb(0_0_0/28%)] ${
        fit === 'contain' ? 'object-contain' : 'object-cover'
      }`}
      data-real-surface
    />
  );
}
