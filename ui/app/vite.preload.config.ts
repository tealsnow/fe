import { defineConfig } from "vite";

export default defineConfig({
  build: {
    rollupOptions: {
      output: {
        entryFileNames: "preload.js",
      },
      external: ["@fe/native"],
    },
    lib: {
      formats: ["es"],
      entry: "src/preload/index.ts",
    },
  },
});
