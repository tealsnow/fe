import { Component, JSX, lazy } from "solid-js";
import { flattenArrayOfObjects } from "../flatten";

import { IconKind } from "./generated/icons";
export * from "./generated/icons";

export type IconComponent = Component<JSX.SvgSVGAttributes<SVGElement>>;
export type Icons = { [key: string]: IconComponent };

const icons: Icons = flattenArrayOfObjects(
  Object.entries(
    import.meta.glob("./icons/*.svg", {
      query: "?component-solid",
    }),
  ).map(([path, func]) => {
    let name = path.split("\\").pop()!.split("/").pop()!;
    name = name.substring(0, name.length - 4);
    return {
      [name]: lazy(() => func() as Promise<{ default: Component }>),
    };
  }),
);

export type IconProps = JSX.SvgSVGAttributes<SVGElement> & {
  kind: IconKind;
  noDefaultStyles?: boolean;
  children?: never;
};

export const Icon = (props: IconProps) => {
  let klass = `stroke-theme-icon-base-stroke fill-theme-icon-base-fill ${props.class}`;
  if (props.noDefaultStyles) klass = props.class ? props.class : "";
  const I = icons[props.kind];
  return <I {...props} class={klass} />;
};
