import * as path from "node:path";
import * as fs from "node:fs";
import * as process from "node:process";

import * as morph from "ts-morph";

//- check and setup

console.log("running `generate_asset_types` script");

const PROJECT_ROOT = process.env.PROJECT_ROOT;

if (!PROJECT_ROOT) {
  console.error(
    "no PROJECT_ROOT env set, make direnv/nix is setup or set it some other way",
  );
  process.exit(1);
}

console.log(`using PROJECT_ROOT as '${PROJECT_ROOT}'`);

const dir_app = path.join(PROJECT_ROOT, "app");
const dir_app_assets = path.join(dir_app, "src/assets");
const dir_app_assets_icons = path.join(dir_app_assets, "icons");
const dir_app_assets_generated = path.join(dir_app_assets, "generated");

const file_tsconfig = path.join(dir_app, "tsconfig.json");

let all_dir_exists = true;
[
  //
  dir_app,
  dir_app_assets,
  dir_app_assets_icons,
  dir_app_assets_generated,
  file_tsconfig,
].forEach((p) => {
  if (!fs.existsSync(p)) {
    console.error(`path "${p}" does not exist`);
    all_dir_exists = false;
  }
});

if (!all_dir_exists) {
  console.error(
    "some path(s) were missing - make sure PROJECT_ROOT is acurately set - aborting",
  );
  process.exit(1);
}

//- gather icon names

let icon_names: string[] = [];
fs.readdirSync(dir_app_assets_icons).forEach((str_path) => {
  const p = path.parse(str_path);
  if (p.ext === ".svg") {
    icon_names.push(p.name);
  } else {
    console.warn(
      `non-svg icon in icons dir('${dir_app_assets_icons}'): '${str_path}'`,
    );
  }
});

const icon_names_strings = icon_names.map((name) => `"${name}"`);

//-

const project = new morph.Project({
  tsConfigFilePath: file_tsconfig,
  skipAddingFilesFromTsConfig: true,
});

const file = project.createSourceFile(
  path.join(dir_app_assets_generated, "icons.ts"),
  "",
  {
    overwrite: true,
  },
);

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
