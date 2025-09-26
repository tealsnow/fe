import Color from "color";

import { DeepPartial } from "~/lib/type_helpers";

import {
  Theme,
  ThemeColors,
  Base16Theme,
  autoThemeColors,
  autoThemeIconTuple,
} from "@fe/theme";
export * from "@fe/theme";

export * from "./Context";
export * from "./ContextProvider";

const gruvbox_dark_hard_base_16: Base16Theme = {
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

export const themeFromBase16 = (
  base16: Base16Theme,
  colors: ThemeColors,
  overrides?: DeepPartial<Theme>,
): Theme => {
  return {
    background: overrides?.background ?? base16.base00,
    text: overrides?.text ?? base16.base05,
    deemphasis: overrides?.deemphasis ?? base16.base04,
    selection: overrides?.selection ?? base16.base02,
    border: overrides?.border ?? base16.base02,
    panel: {
      tab: {
        background: {
          idle: overrides?.panel?.tab?.background?.idle ?? base16.base00,
          active: overrides?.panel?.tab?.background?.active ?? base16.base01,
          dropTarget:
            overrides?.panel?.tab?.background?.dropTarget ?? base16.base03,
        },
      },
    },
    icon: {
      base: autoThemeIconTuple(
        overrides?.icon?.base?.stroke ?? base16.base04,
        overrides?.icon?.base?.fill,
      ),
      active: autoThemeIconTuple(
        overrides?.icon?.active?.stroke ?? base16.base06,
        overrides?.icon?.active?.fill,
      ),
    },
    statusbar: {
      background: overrides?.statusbar?.background ?? base16.base01,
    },
    colors,
    windowRounding: "large",
  };
};

export const defaultTheme = themeFromBase16(
  gruvbox_dark_hard_base_16,
  autoThemeColors({
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
