import tseslint from "@electron-toolkit/eslint-config-ts";
// import eslintConfigPrettier from "@electron-toolkit/eslint-config-prettier";
import eslintPluginSolid from "eslint-plugin-solid";

export default tseslint.config(
  { ignores: ["**/node_modules", "**/dist", "**/out"] },
  tseslint.configs.recommended,
  eslintPluginSolid.configs["flat/typescript"],
  // eslintConfigPrettier,
  {
    rules: {
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
      "@typescript-eslint/explicit-function-return-type": "off", // nope
      "solid/reactivity": [
        "warn",
        {
          customReactiveFunctions: ["cn"],
        },
      ],
    },
  },
);
