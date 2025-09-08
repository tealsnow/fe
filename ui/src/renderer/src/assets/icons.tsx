import { Component, JSX, lazy, mergeProps, splitProps } from "solid-js";

import { flattenArrayOfObjects } from "~/lib/flatten";

import { IconKind } from "./generated/icons";
import { cn } from "~/lib/cn";
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
  children?: never;
};

export const IconProps = {
  noDefaultStyles: false,
};

export const Icon = (inProps: IconProps) => {
  const props = mergeProps(IconProps, inProps);
  const [local, rest] = splitProps(props, ["class", "kind"]);

  // eslint-disable-next-line solid/reactivity
  const I = icons[local.kind];
  return (
    <I
      {...rest}
      class={cn(
        local.kind !== "fe" &&
          "stroke-theme-icon-base-stroke fill-theme-icon-base-fill",
        local.class,
      )}
    />
  );
};
