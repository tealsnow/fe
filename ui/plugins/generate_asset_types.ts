import path from "path";
import fs from "fs";
import process from "process";
import type { Plugin } from "vite";
import * as morph from "ts-morph";

import { createLogger } from "./lib/logger";

const logger = createLogger("generate-asset-types");

export type Options = {
  assetsDir: string;
  tsconfigPath?: string;
};

export default function generateAssetTypesPlugin(opts: Options): Plugin {
  let iconsDirWatcher: fs.FSWatcher | null = null;

  return {
    name: "generate-asset-types",
    buildStart() {
      logger.info("running plugin");

      const dir_assets = opts.assetsDir;
      const dir_assets_icons = path.join(dir_assets, "icons");
      const dir_assets_generated = path.join(dir_assets, "generated");

      const file_tsconfig =
        opts.tsconfigPath ??
        (() => {
          const root = process.cwd();
          return path.join(root, "tsconfig.json");
        })();

      let all_dir_exists = true;
      [
        dir_assets,
        dir_assets_icons,
        dir_assets_generated,
        file_tsconfig,
      ].forEach((p) => {
        if (!fs.existsSync(p)) {
          logger.error(`path "${p}" does not exist`);
          all_dir_exists = false;
        }
      });

      if (!all_dir_exists) {
        logger.error("some path(s) were missing - aborting");
        return;
      }

      // Generate types on build start
      generateIconTypes(dir_assets_icons, dir_assets_generated, file_tsconfig);

      // Set up file watching for icons directory
      if (!iconsDirWatcher) {
        try {
          iconsDirWatcher = fs.watch(
            dir_assets_icons,
            (eventType, _filename) => {
              if (eventType === "rename") {
                logger.info("icons directory changed, regenerating types...");
                generateIconTypes(
                  dir_assets_icons,
                  dir_assets_generated,
                  file_tsconfig,
                );
              }
            },
          );
          logger.info(`watching icons directory: ${dir_assets_icons}`);
        } catch (error) {
          logger.error(`failed to watch icons directory: ${error}`);
        }
      }
    },
    buildEnd() {
      // Clean up the watcher when build ends
      if (iconsDirWatcher) {
        iconsDirWatcher.close();
        iconsDirWatcher = null;
      }
    },
  };
}

function generateIconTypes(
  iconsDir: string,
  generatedDir: string,
  tsConfigPath: string,
): void {
  // Gather icon names
  const icon_names: string[] = [];
  fs.readdirSync(iconsDir).forEach((str_path) => {
    const p = path.parse(str_path);
    if (p.ext === ".svg") {
      icon_names.push(p.name);
    } else {
      logger.warn(`non-svg icon in icons dir ('${iconsDir}'): '${str_path}'`);
    }
  });

  const icon_names_strings = icon_names.map((name) => `"${name}"`);

  const project = new morph.Project({
    tsConfigFilePath: tsConfigPath,
    skipAddingFilesFromTsConfig: true,
  });

  const file_path = path.join(generatedDir, "icons.ts");

  const file = project.createSourceFile(file_path, "", {
    overwrite: true,
  });

  file.addTypeAlias({
    name: "IconKind",
    isExported: true,
    type: icon_names_strings.join(" | "),
  });

  file.addVariableStatement({
    declarationKind: morph.VariableDeclarationKind.Const,
    isExported: true,
    declarations: [
      {
        name: "iconKinds",
        initializer: `[${icon_names_strings.join(", ")}] as const`,
      },
    ],
  });

  file.saveSync();
  logger.info(`wrote file: ${file_path}`);
}
