import { afterEach, describe, expect, it } from '@rstest/core';
import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import { Route, Routes } from 'react-router-dom';
import { App } from './App';
import { site } from './config';
import { docNav, getDocPage } from './docs/content';
import { getTmuxGuide } from './docs/tmux-guide';
import { DocPage } from './pages/DocPage';
import { DocsIndex } from './pages/DocsIndex';
import { DocsLayout } from './pages/DocsLayout';
import { HubPage } from './pages/HubPage';
import { MacosPage } from './pages/MacosPage';
import { TmuxGuidePage } from './pages/TmuxGuidePage';
import { renderWithProviders } from './test/render';

afterEach(() => {
  window.history.replaceState({}, '', '/');
});

function expectAllTmuxLinksToPointTo(path: '/tmux/en' | '/tmux/zh') {
  const links = document.querySelectorAll<HTMLAnchorElement>('a[href^="/tmux/"]');
  expect(links).toHaveLength(4);
  for (const link of links) {
    expect(link).toHaveAttribute('href', path);
  }
}

describe('App hub page', () => {
  it('renders the official homepage around jobs and outcomes', () => {
    renderWithProviders(<App />, { router: false });

    expect(
      screen.getByRole('heading', {
        level: 1,
        name: /Nerve.*Every agent.*One live view/i,
      }),
    ).toBeInTheDocument();

    expect(screen.getByRole('link', { name: /For macOS/i })).toHaveAttribute('href', '/macos');
    expectAllTmuxLinksToPointTo('/tmux/en');
    expect(screen.getByRole('link', { name: /Open docs/i })).toHaveAttribute('href', '/docs');

    // The hero is a brand line and a tagline, and nothing else: no lede
    // paragraph, no per-preview caption, no tmux keybinding on the home page.
    const heading = screen.getByRole('heading', { level: 1 });
    expect(heading.querySelectorAll('span')).toHaveLength(2);
    expect(heading.parentElement?.querySelector('p')).toBeNull();
    expect(screen.queryByText(/prefix \+ e/i)).not.toBeInTheDocument();
  });

  it('links product nav across routes', () => {
    renderWithProviders(<App />, { router: false });
    const productNav = screen.getByRole('navigation', { name: 'Product' });
    expect(within(productNav).getByRole('link', { name: 'Home' })).toHaveAttribute('href', '/');
    expect(within(productNav).getByRole('link', { name: 'Home' })).toHaveAttribute(
      'aria-current',
      'page',
    );
    expect(screen.getAllByRole('link', { name: /^macOS$/i }).length).toBeGreaterThanOrEqual(1);
    expect(screen.getAllByRole('link', { name: /^tmux$/i }).length).toBeGreaterThanOrEqual(1);
  });

  it('opens and closes the mobile product navigation', () => {
    renderWithProviders(<App />, { router: false });

    const trigger = screen.getByRole('button', { name: 'Open navigation' });
    fireEvent.click(trigger);
    expect(trigger).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getByRole('navigation', { name: 'Product mobile' })).toBeInTheDocument();

    fireEvent.keyDown(document, { key: 'Escape' });
    expect(screen.queryByRole('navigation', { name: 'Product mobile' })).not.toBeInTheDocument();
  });

  it('keeps homepage calls to action in the selected language', () => {
    renderWithProviders(<App />, { router: false });

    fireEvent.click(screen.getByRole('menuitemradio', { name: '中文' }));
    expect(screen.getByRole('heading', { level: 1, name: /Nerve.*所有 agent.*一眼看清/ })).toBeInTheDocument();
    expect(within(screen.getByRole('navigation', { name: '产品' })).getByRole('link', { name: '首页' })).toBeInTheDocument();
    expectAllTmuxLinksToPointTo('/tmux/zh');
    expect(screen.queryByRole('link', { name: /For tmux/i })).not.toBeInTheDocument();
  });

  it('keeps Chinese selected while navigating every app surface', async () => {
    renderWithProviders(<App />, { router: false });

    const expectChineseLocale = () => {
      expect(document.documentElement.lang).toBe('zh-Hans');
      expect(screen.getByRole('menuitemradio', { name: '中文' })).toHaveAttribute(
        'aria-checked',
        'true',
      );
      expect(screen.getByLabelText('切换语言')).toBeInTheDocument();
      expect(screen.getByRole('navigation', { name: '产品' })).toBeInTheDocument();
      expect(screen.getByRole('navigation', { name: '页脚' })).toBeInTheDocument();
      expect(screen.queryByLabelText('Switch language')).not.toBeInTheDocument();
      expect(screen.queryByRole('navigation', { name: 'Product' })).not.toBeInTheDocument();
      expect(screen.queryByRole('navigation', { name: 'Footer' })).not.toBeInTheDocument();
    };
    const expectChineseHeading = (englishHeading: RegExp) => {
      expectChineseLocale();
      expect(
        screen.getByRole('heading', { level: 1, name: /[\u3400-\u9fff]/u }),
      ).toBeInTheDocument();
      expect(
        screen.queryByRole('heading', { level: 1, name: englishHeading }),
      ).not.toBeInTheDocument();
    };
    const productNav = () => screen.getByRole('navigation', { name: '产品' });

    fireEvent.click(screen.getByRole('menuitemradio', { name: '中文' }));
    expectChineseHeading(/Every agent.*One live view/i);
    expect(screen.getByText('健康检查失败')).toBeInTheDocument();
    expect(screen.getByText('等你审查')).toBeInTheDocument();
    expect(screen.queryByText('Health check failed')).not.toBeInTheDocument();
    expect(screen.queryByText('Needs your review')).not.toBeInTheDocument();

    fireEvent.click(within(productNav()).getByRole('link', { name: 'macOS' }));
    await waitFor(() => expect(window.location.pathname).toBe('/macos'));
    expectChineseHeading(/Every job.*One glance/i);

    const tmuxLink = within(productNav()).getByRole('link', { name: 'tmux' });
    expect(tmuxLink).toHaveAttribute('href', '/tmux/zh');
    fireEvent.click(tmuxLink);
    await waitFor(() => expect(window.location.pathname).toBe('/tmux/zh'));
    expectChineseHeading(/Stop checking panes.*Get more done/i);

    fireEvent.click(within(productNav()).getByRole('link', { name: '文档' }));
    await waitFor(() => expect(window.location.pathname).toBe('/docs'));
    expectChineseHeading(/The whole protocol, written down/i);

    // The card, not the sidebar entry or the nav CTA — those point at the same
    // route. Structural rather than by name: this test runs in Chinese.
    const getStartedLink = document.querySelector<HTMLAnchorElement>(
      'li > a[href="/docs/get-started"]',
    );
    expect(getStartedLink).not.toBeNull();
    fireEvent.click(getStartedLink as HTMLAnchorElement);
    await waitFor(() => expect(window.location.pathname).toBe('/docs/get-started'));
    expectChineseHeading(/^Get started$/i);
  });

  it('redirects the bare tmux route to the selected language', async () => {
    window.history.replaceState({}, '', '/tmux');
    const english = renderWithProviders(<App />, { router: false });

    await waitFor(() => expect(window.location.pathname).toBe('/tmux/en'));
    english.unmount();

    window.localStorage.setItem('nerve-locale', 'zh');
    window.history.replaceState({}, '', '/tmux');
    renderWithProviders(<App />, { router: false });

    await waitFor(() => expect(window.location.pathname).toBe('/tmux/zh'));
  });
});

describe('macOS marketing page', () => {
  it('renders ribbon hero and major sections', () => {
    renderWithProviders(
      <Routes>
        <Route path="/macos" element={<MacosPage />} />
      </Routes>,
      { router: { initialEntries: ['/macos'] } },
    );

    expect(
      screen.getByRole('heading', {
        level: 1,
        name: new RegExp(`${site.headline[0]}.*${site.headline[1]}`, 'i'),
      }),
    ).toBeInTheDocument();

    expect(screen.getByRole('heading', { name: /Status without another window/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /Everything else is in the docs/i })).toBeInTheDocument();
    expect(screen.queryByText(/127\.0\.0\.1|One conversation is exactly one row/i)).not.toBeInTheDocument();
  });

  it('links to GitHub download', () => {
    renderWithProviders(
      <Routes>
        <Route path="/macos" element={<MacosPage />} />
      </Routes>,
      { router: { initialEntries: ['/macos'] } },
    );
    expect(screen.getByTestId('download-github')).toHaveAttribute('href', site.github);
    expect(screen.getByTestId('install-docs')).toHaveAttribute('href', '/docs/get-started');
  });
});

describe('tmux product pages', () => {
  it('has outcome-focused zh and en product copy', () => {
    expect(getTmuxGuide('zh')?.title.join(' ')).toMatch(/少盯进度.*多做成事/);
    expect(getTmuxGuide('en')?.title.join(' ')).toMatch(/Stop checking panes.*more done/i);
  });

  it('renders the Chinese guide', () => {
    renderWithProviders(
      <Routes>
        <Route path="/tmux/:lang" element={<TmuxGuidePage />} />
      </Routes>,
      { router: { initialEntries: ['/tmux/zh'] } },
    );

    expect(screen.getByRole('heading', { level: 1, name: /少盯进度.*多做成事/ })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /运行、等待、处理/ })).toBeInTheDocument();
    expect(screen.getAllByRole('link', { name: /打开 tmux 文档/ })[0]).toHaveAttribute('href', '/docs/tmux');
    expect(screen.queryByText(/prefix \+ e|j \/ k|nerve\.sh --build/i)).not.toBeInTheDocument();
    expect(document.querySelector('.tmux-hero-terminal-label')).not.toBeInTheDocument();
  });
});

describe('Docs subpages', () => {
  it('lists all handbook cards on the docs index', () => {
    renderWithProviders(
      <Routes>
        <Route path="/docs" element={<DocsLayout />}>
          <Route index element={<DocsIndex />} />
        </Route>
      </Routes>,
      { router: { initialEntries: ['/docs'] } },
    );

    expect(screen.getByRole('heading', { name: /The whole protocol/i })).toBeInTheDocument();
    for (const item of docNav) {
      expect(screen.getByRole('link', { name: new RegExp(`${item.title}.*${item.summary}`, 'i') })).toBeInTheDocument();
    }
  });

  it('renders plugin docs content', () => {
    const page = getDocPage('plugin');
    expect(page).toBeTruthy();

    renderWithProviders(
      <Routes>
        <Route path="/docs" element={<DocsLayout />}>
          <Route path=":slug" element={<DocPage />} />
        </Route>
      </Routes>,
      { router: { initialEntries: ['/docs/plugin'] } },
    );

    expect(screen.getByRole('heading', { level: 1, name: 'Agent plugins' })).toBeInTheDocument();
    expect(screen.getByText(/Subagents are not separate panel rows/i)).toBeInTheDocument();
  });

  it('keeps tmux setup and controls in the docs', () => {
    renderWithProviders(
      <Routes>
        <Route path="/docs" element={<DocsLayout />}>
          <Route path=":slug" element={<DocPage />} />
        </Route>
      </Routes>,
      { router: { initialEntries: ['/docs/tmux'] } },
    );

    expect(screen.getByText(/nerve\.sh --build --tmux --tmux-reload/i)).toBeInTheDocument();
    expect(screen.getAllByText(/prefix \+ e/i).length).toBeGreaterThan(0);
    expect(screen.getByRole('heading', { name: 'Keys' })).toBeInTheDocument();
  });

  it('hub page still mounts under MemoryRouter', () => {
    renderWithProviders(<HubPage />);
    expect(screen.getByRole('heading', { level: 1 })).toBeInTheDocument();
  });
});
