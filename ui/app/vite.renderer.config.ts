import { defineConfig } from "vite";
import solid from "vite-plugin-solid";
import solidSvg from "vite-plugin-solid-svg";
import tailwindcss from "@tailwindcss/vite";
import tsconfigPaths from "vite-tsconfig-paths";

import generateIcons from "./plugins/generateIcons";

export default defineConfig({
  plugins: [
    solid(),
    solidSvg({
      defaultAsComponent: true,
    }),
    generateIcons({
      svgDir: "src/renderer/svg",
      outDir: "src/renderer/ui/Icons",
    }),
    tsconfigPaths(),
    tailwindcss(),
  ],
  clearScreen: false,
});
