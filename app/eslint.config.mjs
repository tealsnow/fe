// @ts-check

import eslint from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  eslint.configs.recommended,
  tseslint.configs.recommended,
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
      "no-debugger": "warn", // What am I not allowed to debug my code?
      "require-yield": "off", // Effect generators
    },
  },
);
