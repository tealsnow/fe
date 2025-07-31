import { flattenZodSchemaPaths } from "./flatten";
import { DeepPartial } from "./type_helpers";
import Color from "color";
import * as z from "zod";

export const ThemeIconTupleSchema = z.object({
  stroke: z.string(),
  fill: z.string(),
});

export const ThemeColorTupleSchema = z.object({
  base: z.string(),
  background: z.string(),
  border: z.string(),
});

export const ThemeColorsSchema = z.object({
  red: ThemeColorTupleSchema,
  orange: ThemeColorTupleSchema,
  yellow: ThemeColorTupleSchema,
  green: ThemeColorTupleSchema,
  aqua: ThemeColorTupleSchema,
  blue: ThemeColorTupleSchema,
  purple: ThemeColorTupleSchema,
  pink: ThemeColorTupleSchema,
});

export const ThemeSchema = z.object({
  background: z.string(),
  text: z.string(),
  border: z.string(),
  panel: z.object({
    tab: z.object({
      background: z.object({
        idle: z.string(),
        active: z.string(),
        dropTarget: z.string(),
      }),
    }),
  }),
  icon: z.object({
    base: ThemeIconTupleSchema,
    active: ThemeIconTupleSchema,
    // disabled, muted
  }),
  statusbar: z.object({
    background: z.string(),
  }),
  colors: ThemeColorsSchema,
});

export type Theme = z.infer<typeof ThemeSchema>;
export type ThemeIconTuple = z.infer<typeof ThemeIconTupleSchema>;
export type ThemeColorTuple = z.infer<typeof ThemeColorTupleSchema>;
export type ThemeColors = z.infer<typeof ThemeColorsSchema>;

export const themeDescFlat = flattenZodSchemaPaths(ThemeSchema);

export const autoThemeIconTuple = (
  stroke: string,
  fill?: string,
): ThemeIconTuple => {
  return {
    stroke,
    fill: fill ?? Color(stroke).fade(0.8).hexa(),
  };
};

export const autoThemeColorTuple = (color: string): ThemeColorTuple => {
  const base = Color(color);
  const background = base.alpha(0.6);
  const border = base.lighten(0.2).alpha(1);
  return {
    base: base.hexa(),
    background: background.hexa(),
    border: border.hexa(),
  };
};

export const autoThemeColors = (colors: {
  red: string;
  orange: string;
  yellow: string;
  green: string;
  aqua: string;
  blue: string;
  purple: string;
  pink: string;
}): ThemeColors => {
  return {
    red: autoThemeColorTuple(colors.red),
    orange: autoThemeColorTuple(colors.orange),
    yellow: autoThemeColorTuple(colors.yellow),
    green: autoThemeColorTuple(colors.green),
    aqua: autoThemeColorTuple(colors.aqua),
    blue: autoThemeColorTuple(colors.blue),
    purple: autoThemeColorTuple(colors.purple),
    pink: autoThemeColorTuple(colors.pink),
  };
};

export type Base16Theme = {
  base00: string; // Default Background
  base01: string; // Lighter Background (Used for status bars, line number and folding marks)
  base02: string; // Selection Background
  base03: string; // Comments, Invisibles, Line Highlighting
  base04: string; // Dark Foreground (Used for status bars)
  base05: string; // Default Foreground, Caret, Delimiters, Operators
  base06: string; // Light Foreground (Not often used)
  base07: string; // Light Background (Not often used)
  base08: string; // Variables, XML Tags, Markup Link Text, Markup Lists, Diff Deleted
  base09: string; // Integers, Boolean, Constants, XML Attributes, Markup Link Url
  base0A: string; // Classes, Markup Bold, Search Text Background
  base0B: string; // Strings, Inherited Class, Markup Code, Diff Inserted
  base0C: string; // Support, Regular Expressions, Escape Characters, Markup Quotes
  base0D: string; // Functions, Methods, Attribute IDs, Headings
  base0E: string; // Keywords, Storage, Selector, Markup Italic, Diff Changed
  base0F: string; // Deprecated, Opening/Closing Embedded Language Tags, e.g. <?php ?>
};

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
    border: overrides?.border ?? base16.base02,
    panel: {
      tab: {
        background: {
          idle: overrides?.panel?.tab?.background?.idle ?? base16.base00,
          active: overrides?.panel?.tab?.background?.active ?? base16.base01,
          dropTarget:
            overrides?.panel?.tab?.background?.dropTarget ?? base16.base07,
        },
      },
    },
    icon: {
      base: autoThemeIconTuple(
        overrides?.icon?.base?.stroke ?? base16.base05,
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

export const applyTheme = (theme: Theme) => {
  themeDescFlat.map((path) => {
    const cssVarName = `--theme-${path.join("-")}`;
    // @ts-ignore: it works
    const value: string = path.reduce((acc, key) => acc[key], theme);
    document.documentElement.style.setProperty(cssVarName, value);
  });
};

const themeDescriptionCssVarNames = () =>
  themeDescFlat.map((p) => {
    const name = p.join("-");
    return { [`theme-${name}`]: `var(--theme-${name})` };
  });

export const tailwindColorsConfig = () => {
  return themeDescriptionCssVarNames().flatten();
};
