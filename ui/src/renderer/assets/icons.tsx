import { Component, JSX, lazy, mergeProps, splitProps } from "solid-js";

import { flattenArrayOfObjects } from "~/lib/flatten";

import { IconKind } from "./generated/icons";
import { cn } from "~/lib/cn";
import { Dynamic } from "solid-js/web";
export * from "./generated/icons";

export type IconComponent = Component<JSX.SvgSVGAttributes<SVGElement>>;
export type Icons = Record<IconKind, IconComponent>;

export const icons: Icons = flattenArrayOfObjects(
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
) as Icons;

export type IconProps = JSX.SvgSVGAttributes<SVGElement> & {
  // kind: IconKind;
  icon: IconComponent;
  children?: never;
  noDefaultStyles?: boolean;
};

export const Icon: Component<IconProps> = (props) => {
  const [local, rest] = splitProps(props, ["class", "icon"]);

  // const icon = (): IconComponent => icons[local.kind];

  return (
    <Dynamic
      component={props.icon}
      {...rest}
      class={cn(
        !props.noDefaultStyles &&
          "stroke-theme-icon-base-stroke fill-theme-icon-base-fill",
        local.class,
      )}
    />
  );
};
