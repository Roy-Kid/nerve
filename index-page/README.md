# Nerve index page

Marketing site for [Nerve](https://github.com/Roy-Kid/nerve) — Rsbuild + React + TypeScript.

## Scripts

```bash
cd index-page
npm install
npm run dev      # http://localhost:3000
npm run build    # static output → dist/
npm run preview  # preview production build
npm test         # rstest
```

## Links

Edit `src/config.ts`:

| Field | Purpose |
|-------|---------|
| `github` | Repository URL |
| `appStore` | App Store product URL |
| `appStoreReady` | `true` when the listing is live (enables the button) |

When the App Store page is published, set:

```ts
appStore: 'https://apps.apple.com/app/idXXXXXXXX',
appStoreReady: true,
```

## Deploy

`npm run build` emits a static site in `dist/`. Host on GitHub Pages, Cloudflare Pages, Netlify, or any static host. `output.assetPrefix` is `./` so relative paths work from a subpath or file server.
