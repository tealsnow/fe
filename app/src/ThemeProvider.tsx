import { createMemo, useContext } from "solid-js";
import { createContext, ParentProps } from "solid-js";
import Theme, { themeCssStyles } from "~/Theme";

type ThemeContext = {
  theme: Theme;
  rootElement: () => HTMLElement;
};
const ThemeContext = createContext<ThemeContext>();

export const useTheme = () => {
  const theme = useContext(ThemeContext);
  if (!theme) throw new Error("useTheme must be used within a ThemeProvider");
  return theme;
};

export type ThemeProviderProps = ParentProps<{
  theme: Theme;
}>;

const ThemeProvider = (props: ThemeProviderProps) => {
  let ref!: HTMLDivElement;

  const prevContext = useContext(ThemeContext);

  return (
    <ThemeContext.Provider
      value={{
        theme: props.theme,
        rootElement: () =>
          // keep the actual root no matter which theme context we are in
          prevContext !== undefined ? prevContext.rootElement() : ref,
      }}
    >
      <div
        ref={ref}
        style={themeCssStyles(props.theme)}
        class="bg-theme-background text-theme-text h-screen w-screen"
      >
        {props.children}
      </div>
    </ThemeContext.Provider>
  );
};

export default ThemeProvider;
