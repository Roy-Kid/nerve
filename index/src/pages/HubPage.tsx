import { Footer } from '../components/Footer';
import {
  HubDocsSection,
  HubHero,
  HubSignalStrip,
  HubSurfacesSection,
} from '../components/hub';
import { Nav } from '../components/Nav';
import { ProductShell } from '../components/ProductShell';

export function HubPage() {
  return (
    <ProductShell>
      <Nav variant="hub" />
      <main>
        <HubHero />
        <HubSignalStrip />
        <HubSurfacesSection />
        <HubDocsSection />
      </main>
      <Footer />
    </ProductShell>
  );
}
