import type { ReactNode } from 'react';
import { cn } from '../lib/utils';

type DeviceFrameProps = {
  variant?: 'default' | 'hero' | 'card';
  className?: string;
  children: ReactNode;
};

/**
 * Shared laptop chrome for every surface preview. There is no off-the-shelf
 * VS Code device drawing — VS Code is an app — so macOS, tmux and VS Code
 * all sit in this one screen + hinge.
 */
export function DeviceFrame({
  variant = 'default',
  className,
  children,
}: DeviceFrameProps) {
  return (
    <div
      className={cn(
        'preview-shell',
        variant !== 'default' && `preview-shell--${variant}`,
        className,
      )}
    >
      <div className={cn('mac-device', variant === 'hero' && 'mac-device--hero')}>
        <div className="mac-screen">
          {children}
          <span className="desktop-camera" aria-hidden="true" />
        </div>
        <div className="mac-base" aria-hidden="true">
          <span />
        </div>
      </div>
    </div>
  );
}
