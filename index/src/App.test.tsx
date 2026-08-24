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
import { renderWithProviders } from './test/render';

afterEach(() => {
  window.history.replaceState({}, '', '/');
});

describe('App hub page', () => {
  it('positions Nerve as a local status product', () => {
    renderWithProviders(<App />, { router: false });

    expect(screen.getByRole('heading', { level: 1, name: 'Nerve' })).toBeInTheDocument();
    expect(
      screen.getByText(/your machines, connected by an open nervous system/i),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/job monitor for long-running work across machines/i),
    ).toBeInTheDocument();

    for (const [name, href] of [
      [/^macOS$/, '/#macos'],
      [/^tmux$/, '/#tmux'],
      [/^VS Code$/, '/#vscode'],
    ] as const) {
      const links = screen.getAllByRole('link', { name });
      expect(links.length).toBeGreaterThan(0);
      for (const link of links) {
        expect(link).toHaveAttribute('href', href);
      }
    }
    expect(screen.getByRole('link', { name: /^Set up macOS$/ })).toHaveAttribute(
      'href',
      '/docs/get-started',
    );
    expect(screen.getByRole('link', { name: /^Read the protocol$/ })).toHaveAttribute(
      'href',
      '/docs/ingest',
    );

    const heading = screen.getByRole('heading', { level: 1 });
    expect(heading.querySelectorAll('span')).toHaveLength(0);
    expect(heading.parentElement?.querySelectorAll('p')).toHaveLength(2);
    expect(screen.queryByText(/prefix \+ e/i)).not.toBeInTheDocument();
  });

  it('uses one viewport per detailed product and surface section', () => {
    renderWithProviders(<App />, { router: false });

    for (const id of ['product', 'macos', 'tmux', 'vscode', 'open']) {
      expect(document.getElementById(id)).toHaveClass('h-svh');
    }
    expect(
      screen.getByRole('heading', { name: /One job list.*Across every machine/i }),
    ).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /whole queue.*menu bar/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /whole queue.*tmux/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /same jobs.*VS Code/i })).toBeInTheDocument();
    expect(
      screen.getByRole('heading', { name: /Bring any producer.*Build any surface/i }),
    ).toBeInTheDocument();

    const hero = screen.getByRole('heading', { level: 1 }).closest('section');
    expect(hero?.querySelectorAll('[data-hero-thumbnail]')).toHaveLength(0);
    expect(hero?.querySelector('.status-ribbon-band')).toBeInTheDocument();
    const previews = Array.from(document.querySelectorAll('[data-surface-preview]'));
    expect(previews).toHaveLength(3);
    expect(previews.map((preview) => preview.getAttribute('data-surface-size'))).toEqual([
      'standard',
      'standard',
      'large',
    ]);
    expect(previews[2]).toHaveClass('max-w-[980px]');
    const realSurfaces = Array.from(document.querySelectorAll<HTMLImageElement>('[data-real-surface]'));
    expect(realSurfaces.map((surface) => surface.getAttribute('src'))).toEqual([
      expect.stringMatching(/surface-tmux\.png$/),
      expect.stringMatching(/surface-vscode\.png$/),
    ]);
  });

  it('links product nav across routes', () => {
    renderWithProviders(<App />, { router: false });
    const productNav = screen.getByRole('navigation', { name: 'Product' });
    expect(within(productNav).getByRole('link', { name: 'Home' })).toHaveAttribute('href', '/');
    expect(within(productNav).getByRole('link', { name: 'Home' })).toHaveAttribute(
      'aria-current',
      'page',
    );
    expect(within(productNav).getByRole('link', { name: 'Docs' })).toHaveAttribute('href', '/docs');
    expect(within(productNav).queryByRole('link', { name: /^macOS$/i })).not.toBeInTheDocument();
    expect(within(productNav).queryByRole('link', { name: /^tmux$/i })).not.toBeInTheDocument();
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
    expect(screen.getByRole('heading', { level: 1, name: 'Nerve' })).toBeInTheDocument();
    expect(screen.getByText(/开放神经系统/)).toBeInTheDocument();
    expect(screen.getByText(/跨机器长时任务监控器/)).toBeInTheDocument();
    expect(within(screen.getByRole('navigation', { name: '产品' })).getByRole('link', { name: '首页' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /完整任务队列.*tmux/ })).toBeInTheDocument();
    expect(
      screen.getByRole('heading', { name: /接入任何发送端.*构建任何显示面/ }),
    ).toBeInTheDocument();
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
    expectChineseLocale();
    expect(screen.getByRole('heading', { level: 1, name: 'Nerve' })).toBeInTheDocument();
    expect(screen.getByText(/开放神经系统/)).toBeInTheDocument();
    expect(screen.getByText(/跨机器长时任务监控器/)).toBeInTheDocument();
    expect(screen.getAllByText('出问题').length).toBeGreaterThan(0);
    expect(screen.getAllByText('需要你').length).toBeGreaterThan(0);
    expect(screen.queryByText('Problem')).not.toBeInTheDocument();
    expect(screen.queryByText('Attention')).not.toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /一个任务列表.*覆盖每台机器/ })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /同一批任务.*VS Code/ })).toBeInTheDocument();

    fireEvent.click(within(productNav()).getByRole('link', { name: '文档' }));
    await waitFor(() => expect(window.location.pathname).toBe('/docs'));
    expectChineseHeading(/The whole protocol, written down/i);

    const getStartedLink = document.querySelector<HTMLAnchorElement>(
      'li > a[href="/docs/get-started"]',
    );
    expect(getStartedLink).not.toBeNull();
    fireEvent.click(getStartedLink as HTMLAnchorElement);
    await waitFor(() => expect(window.location.pathname).toBe('/docs/get-started'));
    expectChineseHeading(/^Get started$/i);
  });

  it('redirects retired surface routes onto homepage sections', async () => {
    window.history.replaceState({}, '', '/macos');
    const macos = renderWithProviders(<App />, { router: false });
    await waitFor(() => {
      expect(window.location.pathname).toBe('/');
      expect(window.location.hash).toBe('#macos');
    });
    macos.unmount();

    window.history.replaceState({}, '', '/tmux');
    const tmux = renderWithProviders(<App />, { router: false });
    await waitFor(() => {
      expect(window.location.pathname).toBe('/');
      expect(window.location.hash).toBe('#tmux');
    });
    tmux.unmount();

    window.localStorage.setItem('nerve-locale', 'zh');
    window.history.replaceState({}, '', '/tmux/zh');
    renderWithProviders(<App />, { router: false });
    await waitFor(() => {
      expect(window.location.pathname).toBe('/');
      expect(window.location.hash).toBe('#tmux');
    });
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

  it('keeps vscode surface docs next to tmux', () => {
    renderWithProviders(
      <Routes>
        <Route path="/docs" element={<DocsLayout />}>
          <Route path=":slug" element={<DocPage />} />
        </Route>
      </Routes>,
      { router: { initialEntries: ['/docs/vscode'] } },
    );

    expect(screen.getByRole('heading', { level: 1, name: 'VS Code extension' })).toBeInTheDocument();
    expect(screen.getByText(/GET \/v1\/stream\?surface=vscode/i)).toBeInTheDocument();
    expect(screen.getByText(/Nerve: Focus Job/i)).toBeInTheDocument();
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
    expect(document.getElementById('vscode')).toBeTruthy();
  });
});

describe('tmux product copy', () => {
  it('describes the concrete tmux surface in zh and en', () => {
    expect(getTmuxGuide('zh')?.title.join(' ')).toMatch(/完整任务队列.*tmux/);
    expect(getTmuxGuide('en')?.title.join(' ')).toMatch(/whole queue.*tmux/i);
  });
});

describe('site surface links', () => {
  it('points retired product paths at homepage hashes', () => {
    expect(site.macos).toBe('/#macos');
    expect(site.tmux).toBe('/#tmux');
    expect(site.vscode).toBe('/#vscode');
  });
});
