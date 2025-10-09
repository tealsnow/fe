export * from "@fe/theme";
export * from "./Context";
export * from "./ContextProvider";
export * from "./Showcase";

import Color from "color";

import * as Theme from "@fe/theme";

const gruvbox_dark_hard_base_16: Theme.Base16Theme = {
  base00: "#1d2021",
  base01: "#3c3836",
  base02: "#504945",
  base03: "#665c54",
  base04: "#bdae93",
  base05: "#d5c4a1",
  base06: "#ebdbb2",
  base07: "#fbf1c7",
  base08: "#fb4934",
  base09: "#fe8019",
  base0A: "#fabd2f",
  base0B: "#b8bb26",
  base0C: "#8ec07c",
  base0D: "#83a598",
  base0E: "#d3869b",
  base0F: "#d65d0e",
};

export const defaultThemeColors = Theme.themeColorsFromBase16(
  gruvbox_dark_hard_base_16,
  Theme.autoColors({
    red: "#cc241d",
    orange: "#fe8019",
    yellow: "#d79921",
    green: "#98971a",
    aqua: "#689d6a",
    blue: "#458588",
    purple: "#b16286",
    pink: "#d4879c",
  }),
  {
    icon: {
      active: {
        fill: Color(gruvbox_dark_hard_base_16.base06)
          .saturate(1)
          .lighten(0.5)
          .fade(0.8)
          .hexa(),
      },
    },
  },
);

export const defaultTheme: Theme.Theme = {
  colors: defaultThemeColors,
  windowRounding: "large",
};
