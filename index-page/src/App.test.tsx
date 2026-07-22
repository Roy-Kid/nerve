import { describe, expect, it } from '@rstest/core';
import { render, screen } from '@testing-library/react';
import { App } from './App';
import { site } from './config';

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
