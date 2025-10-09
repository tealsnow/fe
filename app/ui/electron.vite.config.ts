import { defineConfig, externalizeDepsPlugin } from "electron-vite";
import solid from "vite-plugin-solid";
import solidSvg from "vite-plugin-solid-svg";
import tailwindcss from "@tailwindcss/vite";
import tsconfigPaths from "vite-tsconfig-paths";

import generateIcons from "./plugins/generateIcons";
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
      generateIcons({
        svgDir: "src/renderer/ui/Icons/svg",
        outDir: "src/renderer/ui/Icons",
      }),
      tsconfigPaths(),
      tailwindcss(),
    ],
    clearScreen: false,
  },
});
