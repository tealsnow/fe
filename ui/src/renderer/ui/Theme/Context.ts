import { Match } from "effect";

import createHotStableContext from "~/lib/createHotStableContext";

import Theme from "@fe/theme";

export type TailwindWindowRounding =
  | "rounded-none"
  | "rounded-sm"
  | "rounded-md"
  | "rounded-lg";

export type TransformedTheme = Omit<Theme, "windowRounding"> & {
  windowRounding: TailwindWindowRounding;
  _tag: "transformed";
};

export const TransformedTheme = (
  theme: Theme | TransformedTheme,
): TransformedTheme => {
  if (theme["_tag"] === "transformed") return theme as TransformedTheme;

  return Object.assign(theme, {
    windowRounding: Match.value(theme.windowRounding).pipe(
      Match.withReturnType<TailwindWindowRounding>(),
      Match.when("none", () => "rounded-none"),
      Match.when("small", () => "rounded-sm"),
      Match.when("medium", () => "rounded-md"),
      Match.when("large", () => "rounded-lg"),
      Match.orElse(() => "rounded-none"),
    ),
    _tag: "transformed",
  });
};

export type ThemeContext = {
  theme: () => TransformedTheme;
  rootElement: () => HTMLElement;
};
export const ThemeContext =
  createHotStableContext<ThemeContext>("ThemeContext");
