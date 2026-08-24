import { MacDevicePreview } from '../MacDevicePreview';
import { useLocale } from '../../i18n/locale';
import { HubSurfaceSection } from './HubSurfaceSection';

export function HubMacosSection() {
  const { t } = useLocale();

  return (
    <HubSurfaceSection
      id="macos"
      kicker={t.hub.macos.kicker}
      title={t.macos.headline}
      lede={t.macos.subhead}
      cta={t.macos.openDocs}
      ctaTo="/docs/get-started"
      points={t.macos.truths}
      layout="start"
      ground="page"
    >
      <MacDevicePreview variant="hero" />
    </HubSurfaceSection>
  );
}
