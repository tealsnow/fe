import { Component, JSX } from "solid-js";

import { cn } from "~/lib/cn";
import createBoolTimeout from "~/lib/createBoolTimeout";

import Tooltip from "~/ui/components/Tooltip";
import Icon, { IconKind } from "~/ui/components/Icon";

export const RenderDropPoint: Component<{
  ref?: HTMLDivElement;
  style?: JSX.CSSProperties;
  icon: IconKind;
  tooltip: string;
  hovered: () => boolean;
  class?: string;
  iconClass?: string;
}> = (props) => {
  const delayedOpen = createBoolTimeout(() => props.hovered(), 1000);

  return (
    // @FIXME: we have the control the tooltip
    //   it doesn't open during a drag
    //   this solution is subpar since it doesn't stay open between tooltips
    <Tooltip open={delayedOpen()} placement="top">
      <Tooltip.Trigger
        as="div"
        ref={props.ref}
        style={props.style}
        class={cn(
          "flex items-center justify-center bg-theme-background/80 pointer-events-auto shadow-md z-50 rounded-sm",
          props.class,
        )}
      >
        <Icon
          icon={props.icon}
          class={cn(
            "fill-transparent size-8 transition-colors duration-100",
            props.hovered() && "stroke-theme-icon-active-stroke",
            props.iconClass,
          )}
        />
      </Tooltip.Trigger>
      <Tooltip.Content>{props.tooltip}</Tooltip.Content>
    </Tooltip>
  );
};

export default RenderDropPoint;
