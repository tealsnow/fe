import { Component, JSX, splitProps } from "solid-js";
import { Dynamic } from "solid-js/web";

import cn from "~/lib/cn";

import * as Icons from "~/ui/Icons";
export * as Icons from "~/ui/Icons";
export * from "~/ui/Icons";

export type IconProps = Omit<
  JSX.SvgSVGAttributes<SVGElement>,
  "class" | "children"
> & {
  class?: string;
  icon: Icons.IconComponent | Icons.IconKind;
  children?: never;
};

export const Icon: Component<IconProps> = (props) => {
  const [local, rest] = splitProps(props, ["class", "icon", "children"]);

  return (
    <Dynamic
      component={
        typeof props.icon === "string" ? Icons[props.icon] : props.icon
        // props.icon
      }
      class={cn(
        "stroke-theme-icon-base-stroke fill-theme-icon-base-fill",
        local.class,
      )}
      {...rest}
    />
  );
};

export default Icon;
