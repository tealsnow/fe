import Color from "color";
import { z } from "zod";
import { zx } from "@traversable/zod";

z.config({ jitless: true });

export const ColorKindSchema = z.enum([
  "red",
  "orange",
  "yellow",
  "green",
  "aqua",
  "blue",
  "purple",
  "pink",
]);
export type ColorKind = z.infer<typeof ColorKindSchema>;

export const IconSchema = z.object({
  stroke: z.string(),
  fill: z.string(),
});
export type Icon = z.infer<typeof IconSchema>;

export const ColorTupleSchema = z.object({
  base: z.string(),
  background: z.string(),
  border: z.string(),
});
export type ColorTuple = z.infer<typeof ColorTupleSchema>;

export const ColorsSchema = z.record(ColorKindSchema, ColorTupleSchema);
export type Colors = z.infer<typeof ColorsSchema>;

export const WindowRoundingSchema = z.enum([
  "none",
  "small",
  "medium",
  "large",
]);
export type WindowRounding = z.infer<typeof WindowRoundingSchema>;

export const ThemeColorsSchema = z.object({
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
    base: IconSchema,
    active: IconSchema,
    // muted: ThemeIconTupleSchema,
  }),
  statusbar: z.object({
    background: z.string(),
  }),
  colors: ColorsSchema,
});
export const ThemeColorsSchemaPartial = zx.deepPartial(
  ThemeColorsSchema,
  "applyToOutputType",
);
export type ThemeColors = z.infer<typeof ThemeColorsSchema>;
export type ThemeColorsPartial = z.infer<typeof ThemeColorsSchemaPartial>;

export const ThemeSchema = z.object({
  colors: ThemeColorsSchema,
  windowRounding: WindowRoundingSchema,
});
export type Theme = z.infer<typeof ThemeSchema>;

export const autoIcon = (stroke: string, fill?: string): Icon => {
  return {
    stroke,
    fill: fill ?? Color(stroke).fade(0.8).darken(0.4).alpha(0.2).hexa(),
  };
};

export const autoColorTuple = (color: string): ColorTuple => {
  const base = Color(color);
  const background = base.alpha(0.6);
  const border = base.lighten(0.2).alpha(1);
  return {
    base: base.hexa(),
    background: background.hexa(),
    border: border.hexa(),
  };
};

export const autoColors = (colors: Record<ColorKind, string>): Colors => {
  return {
    red: autoColorTuple(colors.red),
    orange: autoColorTuple(colors.orange),
    yellow: autoColorTuple(colors.yellow),
    green: autoColorTuple(colors.green),
    aqua: autoColorTuple(colors.aqua),
    blue: autoColorTuple(colors.blue),
    purple: autoColorTuple(colors.purple),
    pink: autoColorTuple(colors.pink),
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

export const themeColorsFromBase16 = (
  base16: Base16Theme,
  colors: Colors,
  overrides?: ThemeColorsPartial,
): ThemeColors => {
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
      base: autoIcon(
        overrides?.icon?.base?.stroke ?? base16.base04,
        overrides?.icon?.base?.fill,
      ),
      active: autoIcon(
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
export const flattenZodSchemaPaths = (
  schema: z.ZodTypeAny,
  prefix: string[] = [],
): string[][] => {
  if (schema instanceof z.ZodObject) {
    const shape = schema.shape;

    return Object.entries(shape).flatMap(([key, value]) => {
      return flattenZodSchemaPaths(value, [...prefix, key]);
    });
  }

  if (schema instanceof z.ZodRecord) {
    const keyType = schema.keyType;
    const valueType = schema.valueType;

    if (keyType instanceof z.ZodEnum) {
      return keyType.options.flatMap((key) =>
        // @ts-expect-error 2345: works
        flattenZodSchemaPaths(valueType, [...prefix, key]),
      );
    }

    // @ts-expect-error 2345: works
    return flattenZodSchemaPaths(valueType, [...prefix, "*"]);
  }

  return [prefix];
};

export const themeColorsDescFlat = flattenZodSchemaPaths(ThemeColorsSchema);

export const applyThemeColors = (colors: ThemeColors): void => {
  themeColorsDescFlat.map((path) => {
    const cssVarName = `--theme-${path.join("-")}`;
    // @HACK: typing escape hatch here, it does make sense if you read it
    //   and it works, so bonus points for that
    const value = path.reduce((acc: any, key) => acc[key], colors) as string;
    document.documentElement.style.setProperty(cssVarName, value);
  });
};

export const themeColorsCssStyles = (colors: ThemeColors): string => {
  return themeColorsDescFlat
    .map((path) => {
      const value = path.reduce((acc, key) => (acc as any)[key], colors);
      return `--theme-${path.join("-")}: ${value};`;
    })
    .join(" ");
};

const themeColorsDescriptionCssVarNames = (): Record<string, string>[] =>
  themeColorsDescFlat.map((p) => {
    const name = p.join("-");
    return { [`theme-${name}`]: `var(--theme-${name})` };
  });

export const tailwindColorsConfig = (): Record<string, string> => {
  return flattenArrayOfObjects(themeColorsDescriptionCssVarNames());
};
