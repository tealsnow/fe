import type { Config } from "tailwindcss";

import forms from "@tailwindcss/forms";
import animate from "tailwindcss-animate";

import { tailwindColorsConfig } from "@fe/theme";

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
  plugins: [forms, animate],
} satisfies Config;
