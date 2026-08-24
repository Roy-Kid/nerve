import { defineConfig } from '@rsbuild/core';
import { pluginReact } from '@rsbuild/plugin-react';
import { pluginTailwindcss } from '@rsbuild/plugin-tailwindcss';

export default defineConfig({
  plugins: [pluginReact(), pluginTailwindcss()],
  html: {
    title: 'Nerve — agent status where you already work',
    favicon: './public/favicon-64.png',
    meta: {
      description:
        'Nerve shows every agent and long-running job in the macOS menu bar, tmux, or VS Code, so you know what needs you without checking every window.',
      'og:title': 'Nerve — local agent status',
      'og:description':
        'See what is running, what broke, and what needs you from the macOS menu bar, tmux, or VS Code.',
      'og:image': '/logo.png',
      'theme-color': '#f5f5f7',
    },
    tags: [
      {
        tag: 'link',
        attrs: {
          rel: 'stylesheet',
          href: 'https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&display=swap',
        },
      },
    ],
  },
  output: {
    // Root-relative assets keep direct visits to /tmux/* and /docs/* working.
    assetPrefix: '/',
    distPath: {
      root: 'dist',
    },
  },
  server: {
    port: 3000,
    historyApiFallback: true,
  },
});
