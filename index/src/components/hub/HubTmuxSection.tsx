import { SurfaceScreenshot } from '../SurfaceScreenshot';
import { getTmuxGuide } from '../../docs/tmux-guide';
import { useLocale } from '../../i18n/locale';
import { HubSurfaceSection } from './HubSurfaceSection';

export function HubTmuxSection() {
  const { locale, t } = useLocale();
  const guide = getTmuxGuide(locale);

  if (!guide) return null;

  return (
    <HubSurfaceSection
      id="tmux"
      kicker={t.hub.tmux.kicker}
      title={guide.title}
      lede={guide.lede}
      cta={guide.docsCta}
      ctaTo="/docs/tmux"
      layout="end"
      ground="white"
      points={guide.priority.items.map((item) => ({ title: item.label, body: item.title }))}
    >
      <SurfaceScreenshot
        src="surface-tmux.png"
        alt={t.preview.tmux.label}
        width={1382}
        height={786}
        fit="contain"
      />
    </HubSurfaceSection>
  );
}
