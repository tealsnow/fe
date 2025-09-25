import { useContext, Component, ParentProps } from "solid-js";

import { cn } from "~/lib/cn";

import Theme, { themeCssStyles } from "@fe/theme";

import { ThemeContext, TransformedTheme } from "./Context";

export const ThemeContextProvider: Component<
  ParentProps<{
    theme?: Theme;
    class?: string;
    applyRounding?: boolean;
  }>
> = (props) => {
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
          "bg-theme-background text-theme-text selection:bg-theme-selection",
          props.applyRounding && theme().windowRounding,
          props.class,
        )}
      >
        {props.children}
      </div>
    </ThemeContext.Provider>
  );
};

export const useThemeContext = (): ThemeContext => {
  const theme = useContext(ThemeContext);
  if (!theme) throw new Error("useTheme must be used within a ThemeProvider");
  return theme;
};
