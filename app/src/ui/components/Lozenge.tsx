import { JSX, splitProps, ParentProps } from "solid-js";
import { cva, VariantProps } from "class-variance-authority";

import { ColorKind } from "~/Theme";
import { cn } from "~/lib/cn";

const lozengeStyles = cva(
  "inline-block size-fit text-center content-center bg-(--lozenge-bg)",
  {
    variants: {
      size: {
        medium: "p-1 border-2 min-w-10",
        small: "p-0 px-1 border-1 min-w-6",
      },
      interactive: {
        true: "cursor-pointer transition duration-150 hover:bg-(--lozenge-bg-highlight)",
        false: null,
      },
      highlighted: {
        true: "bg-(--lozenge-bg-highlight)",
        false: null,
      },
      disabled: {
        true: "cursor-default bg-transparent hover:bg-transparent",
        false: null,
      },
    },
    defaultVariants: {
      size: "medium",
      interactive: false,
      highlighted: false,
      disabled: false,
    },
  },
);

export type LozengeProps = Omit<
  JSX.HTMLAttributes<HTMLButtonElement>,
  "disabled"
> &
  Omit<VariantProps<typeof lozengeStyles>, "disabled"> &
  ParentProps<{
    color: ColorKind;
    disabled?: string;
  }>;

/**
 * @deprecated use `~/ui/comonents/Button` instead
 */
export const Lozenge = (props: LozengeProps) => {
  const [local, rest] = splitProps(props, [
    "color",
    "size",
    "interactive",
    "disabled",
    "highlighted",
  ]);

  const isInteractive = local.interactive || rest.onClick !== undefined;

  return (
    <button
      {...(rest as any)}
      style={{
        "--lozenge-bg": `var(--theme-colors-${local.color}-background)`,
        "--lozenge-bg-highlight": `var(--theme-colors-${local.color}-base)`,
        "border-color": `var(--theme-colors-${local.color}-border)`,
      }}
      class={cn(
        lozengeStyles({
          size: local.size,
          interactive: isInteractive,
          disabled: local.disabled !== undefined,
          highlighted: local.highlighted,
        }),
        rest.class as string,
      )}
      title={local.disabled !== undefined ? local.disabled : undefined}
      disabled={local.disabled !== undefined}
      aria-disabled={local.disabled !== undefined || !isInteractive}
    >
      {rest.children}
    </button>
  );
};

export default Lozenge;

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
  Omit<VariantProps<typeof lozengeStyles>, "disabled"> &
  ParentProps<{
    color: ColorKind;
    disabled?: string;

    readOnly?: boolean;
    name?: string;
    value?: string;
    placeholder?: string;
  }>;

export const TextInputLozenge = (props: TextInputLozengeProps) => {
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
