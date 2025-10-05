import type { JSXElement, ValidComponent } from "solid-js";
import { splitProps, type Component } from "solid-js";

import type { PolymorphicProps } from "@kobalte/core/polymorphic";
import * as TooltipPrimitive from "@kobalte/core/tooltip";

import { cn } from "~/lib/cn";

const TooltipTrigger = TooltipPrimitive.Trigger;

const TooltipRoot: Component<TooltipPrimitive.TooltipRootProps> = (props) => {
  return <TooltipPrimitive.Root gutter={4} openDelay={1000} {...props} />;
};

type TooltipContentProps<T extends ValidComponent = "div"> =
  TooltipPrimitive.TooltipContentProps<T> & { class?: string | undefined };

const TooltipContent = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, TooltipContentProps<T>>,
): JSXElement => {
  const [local, others] = splitProps(props as TooltipContentProps, ["class"]);
  return (
    <TooltipPrimitive.Portal>
      <TooltipPrimitive.Content
        class={cn(
          "z-50 origin-[var(--kb-popover-content-transform-origin)] overflow-hidden rounded-sm border bg-theme-background px-1 py-0.5 pt-1 text-sm text-theme-text shadow-md animate-in fade-in-0 zoom-in-95 duration-100 select-text selection:bg-theme-selection",
          local.class,
        )}
        {...others}
      />
    </TooltipPrimitive.Portal>
  );
};

export { TooltipRoot, TooltipTrigger, TooltipContent };

export const Tooltip = Object.assign(TooltipRoot, {
  Trigger: TooltipTrigger,
  Content: TooltipContent,
});
export default Tooltip;
