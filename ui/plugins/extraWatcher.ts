import path from "path";
import { glob } from "glob";

import type { Plugin } from "vite";

const extraWatcher = (globs: string[]): Plugin => ({
  name: "extraWatcher",
  buildStart() {
    for (const item of globs) {
      glob.sync(path.resolve(item)).forEach((filename) => {
        this.addWatchFile(filename);
      });
    }
  },
});

export default extraWatcher;
