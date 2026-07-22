import { describe, expect, it } from '@rstest/core';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { App } from './App';
import { site } from './config';
import { docNav, getDocPage } from './docs/content';
import { DocPage } from './pages/DocPage';
import { DocsIndex } from './pages/DocsIndex';
import { DocsLayout } from './pages/DocsLayout';
import { HomePage } from './pages/HomePage';

describe('App landing page', () => {
  it('renders hero headline and major sections', () => {
    render(<App />);

    expect(
      screen.getByRole('heading', {
        level: 1,
        name: new RegExp(`${site.headline[0]}.*${site.headline[1]}`, 'i'),
      }),
    ).toBeInTheDocument();

    expect(screen.getByRole('heading', { name: /One continuous signal/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /One session/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /Agents report in/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /Private is not/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /Install once/i })).toBeInTheDocument();
    expect(screen.getAllByRole('link', { name: /^Docs$/i }).length).toBeGreaterThanOrEqual(1);
  });

  it('links to GitHub download', () => {
    render(<App />);
    expect(screen.getByTestId('download-github')).toHaveAttribute('href', site.github);
  });

  it('exposes App Store control with target URL', () => {
    render(<App />);
    const el = screen.getByTestId('download-appstore');
    if (site.appStoreReady) {
      expect(el).toHaveAttribute('href', site.appStore);
    } else {
      expect(el).toHaveAttribute('data-href', site.appStore);
    }
  });
});

describe('Docs subpages', () => {
  it('lists all handbook cards on the docs index', () => {
    render(
      <MemoryRouter initialEntries={['/docs']}>
        <Routes>
          <Route path="/docs" element={<DocsLayout />}>
            <Route index element={<DocsIndex />} />
          </Route>
        </Routes>
      </MemoryRouter>,
    );

    expect(screen.getByRole('heading', { name: /Everything that used to live/i })).toBeInTheDocument();
    for (const item of docNav) {
      expect(screen.getByRole('link', { name: new RegExp(`${item.title}.*${item.summary}`, 'i') })).toBeInTheDocument();
    }
  });

  it('renders plugin docs content', () => {
    const page = getDocPage('plugin');
    expect(page).toBeTruthy();

    render(
      <MemoryRouter initialEntries={['/docs/plugin']}>
        <Routes>
          <Route path="/docs" element={<DocsLayout />}>
            <Route path=":slug" element={<DocPage />} />
          </Route>
        </Routes>
      </MemoryRouter>,
    );

    expect(screen.getByRole('heading', { level: 1, name: 'Agent plugins' })).toBeInTheDocument();
    expect(screen.getByText(/Subagents are not separate panel rows/i)).toBeInTheDocument();
  });

  it('home page still mounts under MemoryRouter', () => {
    render(
      <MemoryRouter>
        <HomePage />
      </MemoryRouter>,
    );
    expect(screen.getByRole('heading', { level: 1 })).toBeInTheDocument();
  });
});
