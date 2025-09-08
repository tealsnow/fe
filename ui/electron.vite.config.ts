/// <reference types="vitest" />
import { resolve } from "path";
import { defineConfig, externalizeDepsPlugin } from "electron-vite";
import solid from "vite-plugin-solid";
import solidSvg from "vite-plugin-solid-svg";
import generateAssetTypesPlugin from "./plugins/generate_asset_types";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  main: {
    plugins: [externalizeDepsPlugin()],
  },
  preload: {
    plugins: [externalizeDepsPlugin()],
  },
  renderer: {
    plugins: [
      solid(),
      solidSvg({
        defaultAsComponent: true,
      }),
      generateAssetTypesPlugin(),
      tailwindcss(),
    ],
    resolve: {
      alias: {
        "@renderer": resolve("src/renderer/src"),
        "~": resolve("src/renderer/src"),
      },
    },
    clearScreen: false,
    test: {
      globals: true,
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
  },
});
