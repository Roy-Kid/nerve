import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Footer } from '../components/Footer';
import { Get } from '../components/Get';
import { Nav } from '../components/Nav';
import { Quiet } from '../components/Quiet';
import { Signal } from '../components/Signal';
import { Sources } from '../components/Sources';
import { Stage } from '../components/Stage';
import { Story } from '../components/Story';

export function HomePage() {
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
    <>
      <Nav />
      <main>
        <Stage />
        <Story />
        <Signal />
        <Sources />
        <Quiet />
        <Get />
      </main>
      <Footer />
    </>
  );
}
