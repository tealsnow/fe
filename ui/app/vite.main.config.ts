import { defineConfig } from "vite";

import extraWatcher from "./plugins/extraWatcher";

export default defineConfig({
  plugins: [extraWatcher(["../native/native.*.node"])],
  build: {
    lib: {
      formats: ["es"],
      entry: "src/main/index.ts",
    },
  },
});
