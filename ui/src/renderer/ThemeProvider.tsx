import { useContext } from "solid-js";
import { createContext, ParentProps } from "solid-js";

import { cn } from "~/lib/cn";

import Theme, { themeCssStyles } from "~/Theme";

type ThemeContext = {
  theme: () => Theme;
  rootElement: () => HTMLElement;
};
const ThemeContext = createContext<ThemeContext>();

export const useTheme = () => {
  const theme = useContext(ThemeContext);
  if (!theme) throw new Error("useTheme must be used within a ThemeProvider");
  return theme;
};

export type ThemeProviderProps = ParentProps<{
  theme?: Theme;
  class?: string;
}>;

const ThemeProvider = (props: ThemeProviderProps) => {
  let ref!: HTMLDivElement;

  const prevContext = useContext(ThemeContext);

  const theme = (): Theme => {
    if (props.theme) return props.theme;
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
        class={cn("bg-theme-background text-theme-text", props.class)}
      >
        {props.children}
      </div>
    </ThemeContext.Provider>
  );
};

export default ThemeProvider;
