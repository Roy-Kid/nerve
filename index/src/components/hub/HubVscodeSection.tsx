import { SurfaceScreenshot } from '../SurfaceScreenshot';
import { useLocale } from '../../i18n/locale';
import { HubSurfaceSection } from './HubSurfaceSection';

export function HubVscodeSection() {
  const { t } = useLocale();

  return (
    <HubSurfaceSection
      id="vscode"
      kicker={t.hub.vscode.kicker}
      title={t.vscode.headline}
      lede={t.vscode.subhead}
      cta={t.vscode.openDocs}
      ctaTo="/docs/vscode"
      layout="start"
      visualSize="large"
      ground="page"
      points={t.vscode.truths}
    >
      <SurfaceScreenshot
        src="surface-vscode.png"
        alt={t.preview.vscode.label}
        width={1440}
        height={900}
      />
    </HubSurfaceSection>
  );
}
