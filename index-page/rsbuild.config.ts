import { defineConfig } from '@rsbuild/core';
import { pluginReact } from '@rsbuild/plugin-react';

export default defineConfig({
  plugins: [pluginReact()],
  html: {
    title: 'Nerve — the pulse behind your work',
    favicon: './public/favicon-64.png',
    meta: {
      description:
        'Nerve is a quiet macOS menu-bar ribbon for agents, builds, tests, and long jobs. Local-first. Private by design.',
      'og:title': 'Nerve for macOS',
      'og:description':
        'One continuous menubar pulse for agents and long-running work — without the Dock noise.',
      'og:image': '/logo.png',
      'theme-color': '#f7faff',
    },
    tags: [
      {
        tag: 'link',
        attrs: {
          rel: 'preconnect',
          href: 'https://fonts.googleapis.com',
        },
      },
      {
        tag: 'link',
        attrs: {
          rel: 'preconnect',
          href: 'https://fonts.gstatic.com',
          crossorigin: true,
        },
      },
      {
        tag: 'link',
        attrs: {
          rel: 'stylesheet',
          href: 'https://fonts.googleapis.com/css2?family=Figtree:ital,wght@0,400;0,500;0,600;0,700;1,400&family=Fraunces:ital,opsz,wght@1,9..144,450&family=IBM+Plex+Mono:wght@400;500&family=Syne:wght@600;700;800&display=swap',
        },
      },
    ],
  },
  output: {
    assetPrefix: './',
    distPath: {
      root: 'dist',
    },
  },
  server: {
    port: 3000,
    // SPA: /docs/* falls back to index during local dev.
    historyApiFallback: true,
  },
});
