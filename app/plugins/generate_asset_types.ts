import * as path from "node:path";
import * as fs from "node:fs";
import * as process from "node:process";
import type { Plugin } from "vite";
import * as morph from "ts-morph";
import { createLogger } from "./lib/logger";

// Create logger instance
const logger = createLogger("generate-asset-types");

export default function generateAssetTypesPlugin(): Plugin {
  let iconsDirWatcher: fs.FSWatcher | null = null;

  return {
    name: "generate-asset-types",
    buildStart() {
      logger.info("running plugin");

      const PROJECT_ROOT = process.cwd();

      logger.info(`using PROJECT_ROOT as '${PROJECT_ROOT}'`);

      const dir_app = path.join(PROJECT_ROOT, "src");
      const dir_app_assets = path.join(dir_app, "assets");
      const dir_app_assets_icons = path.join(dir_app_assets, "icons");
      const dir_app_assets_generated = path.join(dir_app_assets, "generated");

      const file_tsconfig = path.join(PROJECT_ROOT, "tsconfig.json");

      let all_dir_exists = true;
      [
        dir_app,
        dir_app_assets,
        dir_app_assets_icons,
        dir_app_assets_generated,
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
      generateIconTypes(
        dir_app_assets_icons,
        dir_app_assets_generated,
        file_tsconfig,
      );

      // Set up file watching for icons directory
      if (!iconsDirWatcher) {
        try {
          iconsDirWatcher = fs.watch(
            dir_app_assets_icons,
            (eventType, _filename) => {
              if (eventType === "rename") {
                logger.info("icons directory changed, regenerating types...");
                generateIconTypes(
                  dir_app_assets_icons,
                  dir_app_assets_generated,
                  file_tsconfig,
                );
              }
            },
          );
          logger.info(`watching icons directory: ${dir_app_assets_icons}`);
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
) {
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
