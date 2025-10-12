import type { ForgeConfig } from "@electron-forge/shared-types";
import { MakerSquirrel } from "@electron-forge/maker-squirrel";
import { MakerZIP } from "@electron-forge/maker-zip";
// import { MakerFlatpak } from "@electron-forge/maker-flatpak";
// import { MakerDeb } from "@electron-forge/maker-deb";
// import { MakerRpm } from "@electron-forge/maker-rpm";
import { VitePlugin } from "@electron-forge/plugin-vite";
import { FusesPlugin } from "@electron-forge/plugin-fuses";
import { FuseV1Options, FuseVersion } from "@electron/fuses";
import { AutoUnpackNativesPlugin } from "@electron-forge/plugin-auto-unpack-natives";

import path from "path";
import * as fs_extra from "fs-extra";
import { dirname } from "path/win32";
import { glob } from "glob";

const config: ForgeConfig = {
  packagerConfig: {
    asar: true,
  },
  rebuildConfig: {},
  makers: [
    new MakerSquirrel({}),
    new MakerZIP({}, ["darwin", "linux"]),
    // new MakerFlatpak({
    //   options: {
    //     id: "me.ketanr.fe",
    //     productName: "Fe",
    //     description: "Fe description",
    //     // branch:
    //     // base:
    //     // baseVersion:
    //     // baseFlatpakref:
    //     // runtime:
    //     // runtimeVersion:
    //     // sdk:
    //     // finishArgs:
    //     files: [],
    //     // modules:
    //     bin: "Fe",
    //     // icon:
    //     categories: ["Development"],
    //     // mimeType:
    //   },
    // }),
    // new MakerRpm({}),
    // new MakerDeb({}),
  ],
  plugins: [
    new VitePlugin({
      // `build` can specify multiple entry builds, which can be Main process, Preload scripts, Worker process, etc.
      // If you are familiar with Vite configuration, it will look really familiar.
      build: [
        {
          // `entry` is just an alias for `build.lib.entry` in the corresponding file of `config`.
          entry: "src/main/index.ts",
          config: "vite.main.config.ts",
          target: "main",
        },
        {
          entry: "src/preload/index.ts",
          config: "vite.preload.config.ts",
          target: "preload",
        },
      ],
      renderer: [
        {
          name: "main_window",
          config: "vite.renderer.config.ts",
        },
      ],
    }),
    // Fuses are used to enable/disable various Electron functionality
    // at package time, before code signing the application
    new FusesPlugin({
      version: FuseVersion.V1,
      [FuseV1Options.RunAsNode]: true,
      [FuseV1Options.EnableCookieEncryption]: true,
      [FuseV1Options.EnableNodeOptionsEnvironmentVariable]: false,
      [FuseV1Options.EnableNodeCliInspectArguments]: false,
      [FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: true,
      [FuseV1Options.OnlyLoadAppFromAsar]: true,
    }),
    new AutoUnpackNativesPlugin({}),
  ],
  hooks: {
    async packageAfterCopy(_forgeConfig, buildPath) {
      const nativePackages = [
        {
          name: "@fe/native",
          // files: ["index.js", "native.*.node"],
        },
      ];

      const dirnamePath = ".";

      const srcPath = path.resolve(dirnamePath, "node_modules");
      const dstPath = path.resolve(buildPath, "node_modules");

      for (const pkg of nativePackages) {
        const srcPkgPath = path.join(srcPath, pkg.name);
        const dstPkgPath = path.join(dstPath, pkg.name);

        await fs_extra.mkdirs(dstPkgPath);

        // for (const file of pkg.files) {
        //   const res = await glob(path.join(srcPkgPath, file));
        //   for (const f of res) {
        //     await fs_extra.copy(path.resolve(f), dstPkgPath, {
        //       recursive: true,
        //       preserveTimestamps: true,
        //       dereference: true,
        //     });
        //   }
        // }
        const entries = await fs_extra.readdir(srcPkgPath);
        await Promise.all(
          entries.map(async (entry) => {
            const srcEntry = path.join(srcPkgPath, entry);
            const destEntry = path.join(dstPkgPath, entry);
            await fs_extra.copy(srcEntry, destEntry, {
              recursive: true,
              preserveTimestamps: true,
              dereference: true,
            });
          }),
        );
      }
    },
  },
};

export default config;
