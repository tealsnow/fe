import type { Config } from "tailwindcss";
import forms from "@tailwindcss/forms";
import { tailwindColorsConfig } from "./theme";

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
  plugins: [forms],
} satisfies Config;
