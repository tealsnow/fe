import type { JSX, ValidComponent } from "solid-js";
import { splitProps } from "solid-js";

import * as ButtonPrimitive from "@kobalte/core/button";
import type { PolymorphicProps } from "@kobalte/core/polymorphic";
import type { VariantProps } from "class-variance-authority";
import { cva } from "class-variance-authority";

import { cn } from "~/lib/cn";
import { ColorKind } from "~/Theme";

// @FIXME: in some cases the focus ring causes the outline to be white
//   not for all variants, but some. I have tried a multitude of fixes, but
//   nothing seems to be working
const buttonVariants = cva(
  "inline-flex items-center justify-center gap-1 whitespace-nowrap text-center content-center transition-colors duration-150 cursor-pointer outline-(--button-border) ring-(--button-border) border-(--button-border) focus-visible:ring-2 focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      size: {
        medium: "p-1 min-w-10 border-2 text-md",
        small: "py-0.5 px-1 min-w-6 border-1 text-sm leading-none size-fit",
        icon: "size-5 border-0",
      },
      variant: {
        default: "bg-(--button-background) hover:bg-(--button-base)",
        outline: "bg-transparent hover:bg-(--button-base)/20",
        ghost: "hover:text-(--button-base) not-hover:border-transparent",
        // @TODO: add a little link icon for this variant
        link: "bg-(--button-background) hover:bg-(--button-base) underline-offset-4 hover:underline",
        icon: "hover:bg-theme-icon-base-fill active:bg-theme-icon-active-fill rounded-sm p-0.5",
      },
      highlighted: {
        true: "bg-(--button-base)",
        false: null,
      },
      disabled: {
        true: "cursor-not-allowed outline-(--button-border)/50 bg-transparent hover:bg-transparent",
        false: null,
      },
    },
    defaultVariants: {
      size: "medium",
      variant: "default",
      highlighted: false,
      disabled: false,
    },
    compoundVariants: [
      {
        size: "icon",
        variant: "default",
        class: "border",
      },
    ],
  },
);

type ButtonProps<T extends ValidComponent = "button"> =
  ButtonPrimitive.ButtonRootProps<T> &
    VariantProps<typeof buttonVariants> & {
      color?: ColorKind | (() => ColorKind);
      class?: string | undefined;
      children?: JSX.Element;
      noOnClickToOnMouseDown?: boolean;
    };

const Button = <T extends ValidComponent = "button">(
  props: PolymorphicProps<T, ButtonProps<T>>,
) => {
  const [, others] = splitProps(props as ButtonProps, [
    "size",
    "variant",
    "highlighted",
    "disabled",
    "color",
    "class",
    "children",
    "noOnClickToOnMouseDown",
  ]);

  const color = () =>
    typeof props.color === "function" ? props.color() : props.color || "aqua";

  // const size = local.variant === "icon" ? "icon" : local.size;
  // const size = props.size;

  // @HACK: this is a small hack to make onClick trigger with onMouseDown instead
  const othersAny = others as any;
  const onClickToOnMouseDown = () =>
    !props.noOnClickToOnMouseDown &&
    othersAny.onClick !== undefined &&
    typeof othersAny.onClick === "function";
  const onClick = othersAny.onClick;
  // if (onClickToOnMouseDown) delete othersAny.onClick;

  return (
    <ButtonPrimitive.Root
      style={{
        "--button-base": `var(--theme-colors-${color()}-base)`,
        "--button-background": `var(--theme-colors-${color()}-background)`,
        "--button-border": `var(--theme-colors-${color()}-border)`,
      }}
      class={cn(
        buttonVariants({
          size: props.size,
          variant: props.variant,
          disabled: props.disabled,
          highlighted: props.highlighted,
        }),
        props.class,
      )}
      {...others}
      onClick={
        // @HACK: since we are handling the onClick as an onMouseDown
        //   we don't want propagation of onClick
        onClickToOnMouseDown()
          ? (e: any) => {
              e.stopPropagation();
            }
          : undefined
      }
      onMouseDown={onClickToOnMouseDown() ? onClick : undefined}
    >
      {props.children}
    </ButtonPrimitive.Root>
  );
};

export { Button, buttonVariants };
export type { ButtonProps };
export default Button;
