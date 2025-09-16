import { JSX, splitProps, ParentProps, Component } from "solid-js";
import { cva, VariantProps } from "class-variance-authority";

import { ColorKind } from "~/Theme";
import { cn } from "~/lib/cn";

const inputLozengeStyles = cva(
  "inline-block size-fit content-center bg-(--lozenge-bg) ring-0",
  {
    variants: {
      size: {
        medium: "p-1 border-2 min-w-40",
        small: "p-0 px-1 border-1 min-w-30",
      },
      highlighted: {
        true: "bg-(--lozenge-bg-highlight) text-white mix-blend-difference",
        false: null,
      },
      disabled: {
        true: "cursor-default bg-transparent hover:bg-transparent",
        false: null,
      },
    },
    defaultVariants: {
      size: "medium",
      highlighted: false,
      disabled: false,
    },
  },
);

export type TextInputLozengeProps = Omit<
  JSX.HTMLAttributes<HTMLInputElement>,
  "disabled"
> &
  Omit<VariantProps<typeof inputLozengeStyles>, "disabled"> &
  ParentProps<{
    color: ColorKind;
    disabled?: string;

    readOnly?: boolean;
    name?: string;
    value?: string;
    placeholder?: string;
  }>;

export const TextInputLozenge: Component<TextInputLozengeProps> = (props) => {
  const [local, rest] = splitProps(props, [
    "size",
    "highlighted",

    "color",
    "disabled",

    "readOnly",
    "name",
    "value",
    "placeholder",
  ]);

  return (
    <input
      type="text"
      readOnly={local.readOnly}
      name={local.name}
      value={local.value}
      placeholder={local.placeholder}
      {...(rest as any)}
      style={{
        "--lozenge-bg": `var(--theme-colors-${local.color}-background)`,
        "--lozenge-bg-highlight": `var(--theme-colors-${local.color}-base)`,
        "border-color": `var(--theme-colors-${local.color}-border)`,
      }}
      size={1}
      class={cn(
        inputLozengeStyles({
          size: local.size,
          disabled: local.disabled !== undefined,
          highlighted: local.highlighted,
        }),
        rest.class as string,
      )}
      title={local.disabled !== undefined ? local.disabled : undefined}
      disabled={local.disabled !== undefined}
      aria-disabled={local.disabled !== undefined}
    >
      {rest.children}
    </input>
  );
};
