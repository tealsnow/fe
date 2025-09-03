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
  noDefaultStyles?: boolean;
  children?: never;
};

export const IconProps = {
  noDefaultStyles: false,
};

export const Icon = (inProps: IconProps) => {
  const props = mergeProps(IconProps, inProps);
  const [, rest] = splitProps(props, ["kind", "noDefaultStyles"]);

  // let klass = `stroke-theme-icon-base-stroke fill-theme-icon-base-fill ${props.class}`;
  let klass = cn(
    "stroke-theme-icon-base-stroke fill-theme-icon-base-fill",
    props.class,
  );
  if (props.noDefaultStyles) klass = props.class ? props.class : "";
  const I = icons[props.kind];
  return (
    <I
      {...rest}
      class={klass}
      // class={
      //   props.noDefaultStyles
      //     ? cn(
      //         "stroke-theme-icon-base-stroke fill-theme-icon-base-fill w-2 h-2",
      //         props.class,
      //       )
      //     : ""
      // }
    />
  );
};
