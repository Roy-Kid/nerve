import { Footer } from './components/Footer';
import { Get } from './components/Get';
import { Nav } from './components/Nav';
import { Quiet } from './components/Quiet';
import { Signal } from './components/Signal';
import { Sources } from './components/Sources';
import { Stage } from './components/Stage';
import { Story } from './components/Story';

export function App() {
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
