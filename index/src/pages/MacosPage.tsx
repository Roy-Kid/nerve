import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Footer } from '../components/Footer';
import { Get } from '../components/Get';
import { Nav } from '../components/Nav';
import { ProductShell } from '../components/ProductShell';
import { Stage } from '../components/Stage';
import { Story } from '../components/Story';

/** macOS menu-bar ribbon marketing page — aligned with hub product chrome. */
export function MacosPage() {
  const { hash } = useLocation();

  useEffect(() => {
    if (!hash) return;
    const id = hash.replace(/^#/, '');
    const el = document.getElementById(id);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  }, [hash]);

  return (
    <ProductShell>
      <Nav variant="macos" />
      <main>
        <Stage />
        <Story />
        <Get />
      </main>
      <Footer />
    </ProductShell>
  );
}
