import { defineConfig } from "@rslib/core";

const sharedDefine = {
  "process.env.NODE_ENV": '"production"',
};

/**
 * VS Code extension host (Node). `autoExternal` is off: the VSIX is
 * packaged `--no-dependencies`, so every import except `vscode` must
 * land in `out/extension.js`.
 *
 * Shape copied from molvis `vsc-ext/rslib.extension.config.mts`. Nerve
 * has no webview in v1, so this is the only bundle.
 */
export default defineConfig({
  lib: [
    {
      format: "cjs",
      bundle: true,
      autoExternal: false,
      autoExtension: false,
      source: {
        entry: { extension: "./src/extension/activate.ts" },
        define: sharedDefine,
      },
      output: {
        target: "node",
        distPath: { root: "out" },
        cleanDistPath: false,
        filename: { js: "extension.js" },
        sourceMap: { js: false },
        externals: { vscode: "commonjs vscode" },
        // Keep names. A 28 kB host bundle is not worth minify renaming
        // `foreignAlias` out from under `focusActionTitle`.
        minify: false,
      },
    },
  ],

  tools: {
    rspack(config) {
      config.optimization = {
        ...config.optimization,
        // Concatenation renamed `foreignAlias` in one module and left a
        // call site in another pointing at the old binding.
        concatenateModules: false,
      };
      config.module = {
        ...config.module,
        parser: {
          ...(config.module?.parser ?? {}),
          javascript: {
            ...(config.module?.parser?.javascript ?? {}),
            exportsPresence: "warn",
          },
        },
      };
    },
  },
});
