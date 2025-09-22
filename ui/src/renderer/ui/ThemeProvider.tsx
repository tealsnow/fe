import { useContext, Component, createContext, ParentProps } from "solid-js";
import { Match } from "effect";

import { cn } from "~/lib/cn";

import Theme, { themeCssStyles } from "~/ui/Theme";

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
export const ThemeContext = createContext<ThemeContext>();

export const useThemeContext = (): ThemeContext => {
  const theme = useContext(ThemeContext);
  if (!theme) throw new Error("useTheme must be used within a ThemeProvider");
  return theme;
};

export type ThemeProviderProps = ParentProps<{
  theme?: Theme;
  class?: string;
  applyRounding?: boolean;
}>;
const ThemeProvider: Component<ThemeProviderProps> = (props) => {
  let ref!: HTMLDivElement;

  const prevContext = useContext(ThemeContext);

  const theme = (): TransformedTheme => {
    if (props.theme) return TransformedTheme(props.theme);
    if (prevContext) return prevContext.theme();
    throw new Error(
      "Attempt to use theme provider without passing a theme or a parent theme provider context",
    );
  };

  return (
    <ThemeContext.Provider
      value={{
        theme: () => theme(),
        rootElement: () =>
          // keep the actual root no matter which theme context we are in
          prevContext !== undefined ? prevContext.rootElement() : ref,
      }}
    >
      <div
        ref={ref}
        style={themeCssStyles(theme())}
        class={cn(
          "bg-theme-background text-theme-text",
          props.applyRounding && theme().windowRounding,
          props.class,
        )}
      >
        {props.children}
      </div>
    </ThemeContext.Provider>
  );
};

export default ThemeProvider;
