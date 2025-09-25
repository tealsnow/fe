import Color from "color";
import * as z from "zod";

// z.config({ jitless: true });

/**
 * Flatten an array of objects into a single object.
 * e.g. `[{ a: 1 }, { b: 2 }]` => `{ a: 1, b: 2 }`
 */
export const flattenArrayOfObjects = function <
  InputValue,
  OutputValue,
  Input extends Record<keyof any, InputValue> | {},
  Output extends Record<keyof any, OutputValue> | {},
>(array: Input[]): Output {
  return array.reduce<Output>((acc, obj) => ({ ...acc, ...obj }), {} as Output);
};

/**
 * Flatten a generic object into a list of leaf paths,
 * e.g. `{ foo: { bar: {}, baz: { a: {}, b: {} }, }, quux: {} }`
 * becomes [["foo", "bar"], ["foo", "baz", "a"], ["foo", "baz", "b"] ["quux"]]
 */
export const flattenObjectToPaths = (
  obj: Record<string, any>,
  prefix: string[] = [],
): string[][] => {
  const paths: string[][] = [];

  for (const key in obj) {
    const value = obj[key];
    const currentPath = [...prefix, key];

    if (value && typeof value === "object" && !Array.isArray(value)) {
      const subPaths = flattenObjectToPaths(value, currentPath);
      paths.push(...subPaths);
    } else {
      paths.push(currentPath);
    }
  }

  // Special case for `{}` leaf objects
  if (Object.keys(obj).length === 0) {
    paths.push(prefix);
  }

  return paths;
};

/**
 * Acts the same as [`flattenObjectToPaths`] but takes a zod schema instead
 */
export function flattenZodSchemaPaths(
  schema: z.ZodTypeAny,
  prefix: string[] = [],
): string[][] {
  if (schema instanceof z.ZodObject) {
    const shape = schema.shape;

    return Object.entries(shape).flatMap(([key, value]) => {
      return flattenZodSchemaPaths(value, [...prefix, key]);
    });
  }

  return [prefix];
}

export type ColorKind =
  | "red"
  | "orange"
  | "yellow"
  | "green"
  | "aqua"
  | "blue"
  | "purple"
  | "pink";

export const colors = [
  "red",
  "orange",
  "yellow",
  "green",
  "aqua",
  "blue",
  "purple",
  "pink",
];

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

export const ThemeWindowRoundingSchema = z.enum([
  "none",
  "small",
  "medium",
  "large",
]);

export const ThemeSchema = z.object({
  background: z.string(),
  text: z.string(),
  deemphasis: z.string(),
  selection: z.string(),
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
  windowRounding: ThemeWindowRoundingSchema,
});

export type ThemeIconTuple = z.infer<typeof ThemeIconTupleSchema>;
export type ThemeColorTuple = z.infer<typeof ThemeColorTupleSchema>;
export type ThemeColors = z.infer<typeof ThemeColorsSchema>;
export type ThemeWindowRounding = z.infer<typeof ThemeWindowRoundingSchema>;

export type Theme = z.infer<typeof ThemeSchema>;
export default Theme;

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

export const themeDescFlat = flattenZodSchemaPaths(ThemeSchema);

export const applyTheme = (theme: Theme): void => {
  themeDescFlat.map((path) => {
    const cssVarName = `--theme-${path.join("-")}`;
    // @HACK: typing escape hatch here, it does make sense if you read it
    //   and it works, so bonus points for that
    const value = path.reduce((acc: any, key) => acc[key], theme) as string;
    document.documentElement.style.setProperty(cssVarName, value);
  });
};

export const themeCssStyles = (
  theme: Omit<Theme, "windowRounding">,
): string => {
  return themeDescFlat
    .map((path) => {
      const value = path.reduce((acc, key) => (acc as any)[key], theme);
      return `--theme-${path.join("-")}: ${value};`;
    })
    .join(" ");
};

const themeDescriptionCssVarNames = (): Record<string, string>[] =>
  themeDescFlat.map((p) => {
    const name = p.join("-");
    return { [`theme-${name}`]: `var(--theme-${name})` };
  });

export const tailwindColorsConfig = (): Record<string, string> => {
  return flattenArrayOfObjects(themeDescriptionCssVarNames());
};

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
