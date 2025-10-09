import { defineConfig, mergeConfig } from "vitest/config";
import viteConfig from "./electron.vite.config";

export default mergeConfig(
  viteConfig.renderer,
  defineConfig({
    test: {
      globals: false,
      // environment: 'jsdom',
      // setupFiles: "./test/setup.ts",
      include: ["src/**/*.{test,spec}.{ts,tsx}"],
      disableConsoleIntercept: false,
      chaiConfig: {
        truncateThreshold: 0,
        showDiff: true,
        includeStack: true,
      },
    },
  }),
);
