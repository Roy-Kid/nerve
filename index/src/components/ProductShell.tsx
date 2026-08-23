import type { ReactNode } from 'react';

type ProductShellProps = {
  children: ReactNode;
};

/** Shared page chrome for hub / macOS / tmux — not docs. */
export function ProductShell({ children }: ProductShellProps) {
  return <div className="min-h-screen bg-page text-label">{children}</div>;
}
