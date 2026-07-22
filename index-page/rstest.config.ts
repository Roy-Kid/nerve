import { pluginReact } from '@rsbuild/plugin-react';
import { defineConfig } from '@rstest/core';

export default defineConfig({
  plugins: [pluginReact()],
  testEnvironment: 'happy-dom',
  setupFiles: ['./rstest.setup.ts'],
  include: ['src/**/*.{test,spec}.{ts,tsx}'],
});
