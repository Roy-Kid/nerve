import { render, type RenderOptions } from '@testing-library/react';
import type { ReactElement, ReactNode } from 'react';
import { MemoryRouter, type MemoryRouterProps } from 'react-router-dom';
import { LocaleProvider } from '../i18n/locale';

type Options = RenderOptions & {
  router?: MemoryRouterProps | false;
};

export function renderWithProviders(ui: ReactElement, options: Options = {}) {
  const { router = { initialEntries: ['/'] }, ...renderOptions } = options;

  function Wrapper({ children }: { children: ReactNode }) {
    const content =
      router === false ? children : <MemoryRouter {...router}>{children}</MemoryRouter>;

    return <LocaleProvider>{content}</LocaleProvider>;
  }

  return render(ui, { wrapper: Wrapper, ...renderOptions });
}
