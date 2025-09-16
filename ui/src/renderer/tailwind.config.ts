import type { Config } from "tailwindcss";
import forms from "@tailwindcss/forms";
import { tailwindColorsConfig } from "./ui/Theme";

export default {
  content: [
    "../index.html",
    "./**/*.{js,ts,jsx,tsx,css,md,mdx,html,json,scss}",
  ],
  theme: {
    extend: {
      colors: {
        ...tailwindColorsConfig(),
      },
    },
  },
  plugins: [
    forms,
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    require("tailwindcss-animate"),
  ],
} satisfies Config;
