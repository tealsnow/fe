import { Component, onMount, onCleanup, createSignal } from "solid-js";
import { Effect, Order, pipe } from "effect";
import { css } from "solid-styled-components";

import { draggable } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";

import cn from "~/lib/cn";
import Percent from "~/lib/Percent";
import assert from "~/lib/assert";
import Integer from "~/lib/Integer";
import UpdateFn from "~/lib/UpdateFn";

import { useContext } from "../Context";
import {
  PanelNode,
  SplitAxis,
  SplitChild,
  splitUpdateChildPercent,
} from "../data";

export const SplitResizeHandle: Component<{
  updateSplit: UpdateFn<PanelNode.Split>;
  currentChild: () => SplitChild;
  nextChild: () => SplitChild;
  idx: () => number;
  axis: () => SplitAxis;
}> = (props) => {
  const ctx = useContext();

  const [resizing, setResizing] = createSignal(false);

  let ref!: HTMLDivElement;
  onMount(() => {
    const cleanup = draggable({
      element: ref,

      onGenerateDragPreview: ({ nativeSetDragImage }) => {
        disableNativeDragPreview({ nativeSetDragImage });
      },
      onDragStart: () => {
        console.groupCollapsed("PanelNode split resize");
        console.log("drag start");

        setResizing(true);

        preventUnhandled.start();

        ctx.historyBatchBegin();
      },
      onDrop: () => {
        console.log("drag stop");

        setResizing(false);

        preventUnhandled.stop();

        console.groupEnd();
        ctx.historyBatchEnd();
      },

      getInitialData: () => {
        const parentRect = ref.parentElement?.getBoundingClientRect();
        assert(parentRect !== undefined);

        const parentSizes: Record<SplitAxis, number> = {
          vertical: parentRect.height,
          horizontal: parentRect.width,
        };
        const parentSize = parentSizes[props.axis()];

        const currentSize = parentSize * props.currentChild().percent;
        const nextSize = parentSize * props.nextChild().percent;

        return {
          parentSize,
          currentSize,
          nextSize,
        };
      },

      onDrag: ({ location, source }) => {
        console.log("on drag");

        const parentSize = source.data.parentSize as number;
        const currentSize = source.data.currentSize as number;
        const nextSize = source.data.nextSize as number;

        const deltas: Record<SplitAxis, () => number> = {
          vertical: () =>
            location.current.input.clientY - location.initial.input.clientY,
          horizontal: () =>
            location.current.input.clientX - location.initial.input.clientX,
        };
        const delta = deltas[props.axis()]();

        const totalAvailableSpace = currentSize + nextSize;
        const margin = parentSize * 0.05;

        const clamp = Order.clamp(Order.number)({
          minimum: margin,
          maximum: totalAvailableSpace - margin,
        });
        const newCurrentSize = clamp(currentSize + delta);
        const newNextSize = clamp(nextSize - delta);

        const newCurrentPercent = newCurrentSize / parentSize;
        const newNextPercent = newNextSize / parentSize;

        console.log(
          "new current",
          newCurrentPercent,
          "new next",
          newNextPercent,
        );

        // false positive
        // eslint-disable-next-line solid/reactivity
        props.updateSplit((split) =>
          pipe(
            splitUpdateChildPercent({
              split,
              idx: Integer(props.idx()),
              percent: Percent(newCurrentPercent),
            }),
            Effect.flatMap((split) =>
              splitUpdateChildPercent({
                split,
                idx: Integer(props.idx() + 1),
                percent: Percent(newNextPercent),
              }),
            ),
            Effect.runSync,
          ),
        );
      },
    });
    onCleanup(() => cleanup());
  });

  return <ResizeHandleImpl ref={ref} axis={props.axis()} resizing={resizing} />;
};

export const WorkspaceResizeHandle: Component<{
  axis: SplitAxis;
  size: Percent;
  updateSize: (size: Percent) => void;
  sign: "+" | "-";
}> = (props) => {
  const ctx = useContext();

  const [resizing, setResizing] = createSignal(false);

  let ref!: HTMLDivElement;
  onMount(() => {
    const cleanup = draggable({
      element: ref,

      onGenerateDragPreview: ({ nativeSetDragImage }) => {
        disableNativeDragPreview({ nativeSetDragImage });
      },
      onDragStart: () => {
        console.groupCollapsed("workspace split resize");
        console.log("drag start");

        setResizing(true);

        preventUnhandled.start();

        ctx.historyBatchBegin();
      },
      onDrop: () => {
        console.log("drag stop");

        setResizing(false);

        preventUnhandled.stop();

        console.groupEnd();
        ctx.historyBatchEnd();
      },

      getInitialData: () => {
        const parentRect = ref.parentElement?.getBoundingClientRect();
        assert(parentRect !== undefined);

        const parentSizes: Record<SplitAxis, number> = {
          vertical: parentRect.height,
          horizontal: parentRect.width,
        };
        const parentSize = parentSizes[props.axis];

        const currentSize = parentSize * props.size;

        return {
          parentSize,
          currentSize,
        };
      },

      onDrag: ({ location, source }) => {
        console.log("on drag");

        const parentSize = source.data.parentSize as number;
        const currentSize = source.data.currentSize as number;

        const deltas: Record<SplitAxis, () => number> = {
          vertical: () =>
            location.current.input.clientY - location.initial.input.clientY,
          horizontal: () =>
            location.current.input.clientX - location.initial.input.clientX,
        };
        const delta = deltas[props.axis]();

        const margin = parentSize * 0.05;

        const clamp = Order.clamp(Order.number)({
          minimum: margin,
          maximum: parentSize - margin,
        });
        const newCurrentSize = clamp(
          props.sign === "+" ? currentSize + delta : currentSize - delta,
        );

        const newCurrentPercent = newCurrentSize / parentSize;

        console.log("new size", newCurrentPercent);

        props.updateSize(Percent(newCurrentPercent));
      },
    });
    onCleanup(() => cleanup());
  });

  return <ResizeHandleImpl ref={ref} axis={props.axis} resizing={resizing} />;
};

export const ResizeHandleImpl: Component<{
  ref?: HTMLDivElement;
  axis: SplitAxis;
  resizing: () => boolean;
}> = (props) => {
  const axisStyles: Record<SplitAxis, string> = {
    vertical: "h-[1px] w-full",
    horizontal: "w-[1px] h-full",
  };

  const pseudoStyles: Record<SplitAxis, string> = {
    vertical: `
      cursor: ns-resize;
      width: 100%;
      height: 7px;
      top: -3px;
    `,
    horizontal: `
      cursor: ew-resize;
      height: 100%;
      width: 7px;
      left: -3px;
    `,
  };

  return (
    <div
      ref={props.ref}
      class={cn(
        "relative bg-theme-border hover:bg-theme-deemphasis transition-colors duration-100",
        axisStyles[props.axis],
        props.resizing() && "bg-theme-deemphasis",
        css`
          &::before {
            content: "";
            position: absolute;
            z-index: 10;
            ${pseudoStyles[props.axis]}
          }
        `,
      )}
    />
  );
};
