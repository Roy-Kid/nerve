import { useEffect, useState } from 'react';

/** Normalized pointer position in viewport: x/y ∈ [0,1]. */
export function usePointer() {
  const [pos, setPos] = useState({ x: 0.5, y: 0.35 });

  useEffect(() => {
    const onMove = (e: PointerEvent) => {
      setPos({
        x: e.clientX / window.innerWidth,
        y: e.clientY / window.innerHeight,
      });
    };
    window.addEventListener('pointermove', onMove, { passive: true });
    return () => window.removeEventListener('pointermove', onMove);
  }, []);

  return pos;
}
