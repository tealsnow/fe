import { defineConfig, externalizeDepsPlugin } from "electron-vite";
import solid from "vite-plugin-solid";
import solidSvg from "vite-plugin-solid-svg";
import tailwindcss from "@tailwindcss/vite";
import tsconfigPaths from "vite-tsconfig-paths";

import generateAssetTypesPlugin from "./plugins/generate_asset_types";
import extraWatcher from "./plugins/extraWatcher";

export default defineConfig({
  main: {
    plugins: [
      externalizeDepsPlugin(),
      extraWatcher(["../native/native.*.node"]),
    ],
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
      generateAssetTypesPlugin({ assetsDir: "src/renderer/assets" }),
      tsconfigPaths(),
      tailwindcss(),
    ],
    clearScreen: false,
  },
});
