import { useContext as solidUseContext, ParentComponent } from "solid-js";

import { cn } from "~/lib/cn";

import * as Theme from "@fe/theme";

import { Context, TransformedTheme } from "./Context";

export const Provider: ParentComponent<{
  theme?: Theme.Theme;
  class?: string;
  applyRounding?: boolean;
}> = (props) => {
  let ref!: HTMLDivElement;

  const prevContext = solidUseContext(Context);

  const theme = (): TransformedTheme => {
    if (props.theme) return TransformedTheme(props.theme);
    if (prevContext) return prevContext.theme();
    throw new Error(
      "Attempt to use theme provider without passing a theme or a parent theme provider context",
    );
  };

  return (
    <Context.Provider
      value={{
        theme: () => theme(),
        rootElement: () =>
          // keep the actual root no matter which theme context we are in
          prevContext !== undefined ? prevContext.rootElement() : ref,
      }}
    >
      <div
        ref={ref}
        style={Theme.themeColorsCssStyles(theme().colors)}
        class={cn(
          "text-theme-text selection:bg-theme-selection",
          props.applyRounding && theme().windowRounding,
          props.class,
        )}
      >
        {props.children}
      </div>
    </Context.Provider>
  );
};

export const useContext = (): Context => {
  const theme = solidUseContext(Context);
  if (!theme)
    throw new Error(
      "cannot use Theme Context outside of a Theme Context Provider",
    );
  return theme;
};
