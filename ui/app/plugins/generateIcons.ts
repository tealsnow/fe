import path from "path";
import fs from "fs";
import type { Plugin, Rollup } from "vite";
import * as morph from "ts-morph";

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
      this.info("running plugin");

      if (!fs.existsSync(opts.svgDir)) {
        this.error(`svg dir does not exist "${opts.svgDir}"`);
        return;
      }
      if (!fs.existsSync(opts.outDir)) {
        this.error(`output dir does not exist "${opts.outDir}"`);
        return;
      }

      const tsconfigPath =
        opts.tsconfigPath ??
        (() => {
          const root = process.cwd();
          return path.join(root, "tsconfig.json");
        })();

      generateIcons(this, {
        ...opts,
        tsConfigPath: tsconfigPath,
      });

      if (process.env.NODE_ENV !== "development") return;

      if (!iconsDirWatcher) {
        try {
          iconsDirWatcher = fs.watch(opts.svgDir, (eventType, _filename) => {
            if (eventType === "rename") {
              this.info("svg directory changed, regenerating...");
              generateIcons(this, {
                ...opts,
                tsConfigPath: tsconfigPath,
              });
            }
          });
          this.info(`watching svg directory: ${opts.svgDir}`);
        } catch (error) {
          this.error(`failed to watch svg directory: ${error}`);
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
  ctx: Rollup.PluginContext,
  opts: Omit<Options, "tsconfigPath"> & { tsConfigPath: string },
): void => {
  // fs.readdir(opts.outDir, (err, files) => {
  //   if (err) throw err;

  //   for (const file of files) {
  //     fs.unlink(path.join(opts.outDir, file), (err) => {
  //       if (err) throw err;
  //     });
  //   }
  // });

  const iconNames: string[] = [];
  fs.readdirSync(opts.svgDir).forEach((strPath) => {
    const p = path.parse(strPath);
    if (p.ext === ".svg") {
      iconNames.push(p.name);
    } else {
      ctx.warn(`non-svg icon in icons dir ('${opts.svgDir}'): '${strPath}'`);
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

    const iconPath = path.relative(
      path.resolve(opts.outDir),
      path.resolve(opts.svgDir, `${iconName}.svg`),
    );

    const componentCode = `
import Icon from "${iconPath}";
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
