import tseslint from "@electron-toolkit/eslint-config-ts";
import eslintPluginSolid from "eslint-plugin-solid";
import { defineConfig } from "eslint/config";

export default defineConfig(
  {
    ignores: [
      "node_modules/**",
      "out/**",
      ".vite/**",
      "src/renderer/ui/Icons/**/*",
    ],
  },
  tseslint.configs.recommended,
  eslintPluginSolid.configs["flat/typescript"],
  {
    rules: {
      "no-unassigned-vars": "off",
      // Kinda stupid I have to configure this
      "@typescript-eslint/no-unused-vars": [
        "warn",
        {
          args: "all",
          argsIgnorePattern: "^_",
          caughtErrors: "all",
          caughtErrorsIgnorePattern: "^_",
          destructuredArrayIgnorePattern: "^_",
          varsIgnorePattern: "^_",
          ignoreRestSiblings: true,
        },
      ],
      "@typescript-eslint/no-empty-object-type": "off", // I mean what?
      "@typescript-eslint/no-explicit-any": "off", // I mean its explicit and can be useful sometimes
      "@typescript-eslint/no-namespace": "off", // namespaces are useful
      "no-debugger": "warn", // What am I not allowed to debug my code?
      "require-yield": "off", // Effect generators
      "solid/reactivity": "warn",
      "@typescript-eslint/explicit-function-return-type": "warn",
      // gets in the way during dev and well its pretty easy to tell if a
      // function is empty + just putting a comment in it stops the error
      "@typescript-eslint/no-empty-function": "off",
    },
  },
);
