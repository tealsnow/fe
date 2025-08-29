import { ParentProps } from "solid-js";
import Theme, { themeCssStyles } from "~/Theme";

export type ThemeProviderProps = ParentProps<{
  theme: Theme;
}>;

const ThemeProvider = (props: ThemeProviderProps) => {
  return <div style={themeCssStyles(props.theme)}>{props.children}</div>;
};
export default ThemeProvider;
