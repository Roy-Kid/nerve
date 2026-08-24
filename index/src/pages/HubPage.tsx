import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Footer } from '../components/Footer';
import {
  HubDocsSection,
  HubHero,
  HubMacosSection,
  HubSignalStrip,
  HubTmuxSection,
  HubVscodeSection,
} from '../components/hub';
import { Nav } from '../components/Nav';
import { ProductShell } from '../components/ProductShell';

export function HubPage() {
  const { hash } = useLocation();

  useEffect(() => {
    if (!hash) return;
    const id = hash.replace(/^#/, '');
    const el = document.getElementById(id);
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }, [hash]);

  return (
    <ProductShell>
      <Nav variant="hub" />
      <main>
        <HubHero />
        <HubSignalStrip />
        <HubMacosSection />
        <HubTmuxSection />
        <HubVscodeSection />
        <HubDocsSection />
      </main>
      <Footer />
    </ProductShell>
  );
}
