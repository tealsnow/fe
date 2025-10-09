import path from "path";
import fs from "fs";
import type { Plugin } from "vite";
import * as morph from "ts-morph";

import { createLogger } from "./lib/logger";

const logger = createLogger("generateIcons");

export type Options = {
  svgDir: string;
  outDir: string;
  tsconfigPath?: string;
};

export default function generateIconsPlugin(opts: Options): Plugin {
  let iconsDirWatcher: fs.FSWatcher | null = null;

  return {
    name: "generateIcons",
    buildStart() {
      logger.info("running plugin");

      if (!fs.existsSync(opts.svgDir)) {
        logger.error(`svg dir does not exist "${opts.svgDir}"`);
        return;
      }
      if (!fs.existsSync(opts.outDir)) {
        logger.error(`output dir does not exist "${opts.outDir}"`);
        return;
      }

      const tsconfigPath =
        opts.tsconfigPath ??
        (() => {
          const root = process.cwd();
          return path.join(root, "tsconfig.json");
        })();

      generateIcons({
        ...opts,
        tsConfigPath: tsconfigPath,
      });

      if (!iconsDirWatcher) {
        try {
          iconsDirWatcher = fs.watch(opts.svgDir, (eventType, _filename) => {
            if (eventType === "rename") {
              logger.info("svg directory changed, regenerating...");
              generateIcons({
                ...opts,
                tsConfigPath: tsconfigPath,
              });
            }
          });
          logger.info(`watching svg directory: ${opts.svgDir}`);
        } catch (error) {
          logger.error(`failed to watch svg directory: ${error}`);
        }
      }
    },
    buildEnd() {
      if (iconsDirWatcher) {
        iconsDirWatcher.close();
        iconsDirWatcher = null;
      }
    },
  };
}

const snakeToCapitalCamelCase = (snakeCaseString: string): string =>
  snakeCaseString
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join("");

const generateIcons = (
  opts: Omit<Options, "tsconfigPath"> & { tsConfigPath: string },
): void => {
  const iconNames: string[] = [];
  fs.readdirSync(opts.svgDir).forEach((strPath) => {
    const p = path.parse(strPath);
    if (p.ext === ".svg") {
      iconNames.push(p.name);
    } else {
      logger.warn(`non-svg icon in icons dir ('${opts.svgDir}'): '${strPath}'`);
    }
  });

  const iconNamesCamelCase = iconNames.map(snakeToCapitalCamelCase);

  const iconComponentCode = `
import { Component, JSX } from "solid-js";
type IconComponent = Component<JSX.SvgSVGAttributes<SVGElement>>;
export default IconComponent;
`.trim();

  fs.writeFileSync(
    path.join(opts.outDir, "IconComponent.tsx"),
    iconComponentCode,
  );

  for (let i = 0; i < iconNames.length; i += 1) {
    const iconName = iconNames[i];
    const name = iconNamesCamelCase[i];

    const componentCode = `
import Icon from "./svg/${iconName}.svg";
export default Icon;
    `.trim();

    fs.writeFileSync(path.join(opts.outDir, `${name}.tsx`), componentCode);
  }

  const project = new morph.Project({
    tsConfigFilePath: opts.tsConfigPath,
    skipAddingFilesFromTsConfig: true,
  });

  const indexFilePath = path.join(opts.outDir, "index.ts");

  const indexFile = project.createSourceFile(indexFilePath, "", {
    overwrite: true,
  });

  indexFile.addImportDeclaration({
    namedImports: ["lazy"],
    moduleSpecifier: "solid-js",
  });

  for (const name of iconNamesCamelCase) {
    indexFile.addVariableStatement({
      declarationKind: morph.VariableDeclarationKind.Const,
      isExported: true,
      declarations: [
        {
          name,
          type: "IconComponent",
          initializer: `lazy(() => import("./${name}"))`,
        },
      ],
      leadingTrivia: "// @ts-expect-error 2322\n",
    });
  }
  indexFile.addImportDeclaration({
    isTypeOnly: true,
    defaultImport: "IconComponent",
    moduleSpecifier: "./IconComponent",
  });

  indexFile.addVariableStatement({
    declarationKind: morph.VariableDeclarationKind.Const,
    isExported: true,
    declarations: [
      {
        name: "IconKind",
        initializer: `[${iconNamesCamelCase.map((s) => `"${s}"`).join(", ")}] as const`,
      },
    ],
  });

  indexFile.addTypeAlias({
    name: "IconKind",
    isExported: true,
    type: "(typeof IconKind)[number]",
  });

  indexFile.addExportDeclaration({
    isTypeOnly: true,
    namedExports: ["IconComponent"],
  });

  indexFile.saveSync();
};
