/* @refresh reload */

import {
  Component,
  Index,
  onMount,
  Show,
  onCleanup,
  createSignal,
  Setter,
  Accessor,
  For,
  JSX,
} from "solid-js";
import { Option, Match, Array } from "effect";

import { dropTargetForElements } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { CleanupFn } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";

import cn from "~/lib/cn";
import assert from "~/lib/assert";
import Integer from "~/lib/Integer";
import UpdateFn from "~/lib/UpdateFn";

import { PanelNode, SplitAxis } from "../data";

import { DragDataForTab, DropSide, DropTargetSplitInsert } from "./dnd";
import ViewPanelNode from "./PanelNode";
import { SplitResizeHandle } from "./ResizeHandle";
import RenderDropPoint from "./RenderDropPoint";

export const ViewPanelNodeSplit: Component<{
  split: () => PanelNode.Split;
  updateSplit: UpdateFn<PanelNode.Split>;
}> = (props) => {
  const axis = (): SplitAxis => props.split().axis;

  const layoutSize: Record<SplitAxis, "height" | "width"> = {
    vertical: "height",
    horizontal: "width",
  };

  const layoutDirection: Record<SplitAxis, "flex-col" | "flex-row"> = {
    vertical: "flex-col",
    horizontal: "flex-row",
  };

  const layoutFullAxis: Record<SplitAxis, "w-full" | "h-full"> = {
    vertical: "w-full",
    horizontal: "h-full",
  };

  const [tabHovered, setTabHovered] = createSignal(false);

  let ref!: HTMLDivElement;

  onMount(() => {
    const cleanup = dropTargetForElements({
      element: ref,

      onDragStart: ({ source }) => {
        if (DragDataForTab.$is(source.data)) setTabHovered(true);
      },
      onDragEnter: ({ source }) => {
        if (DragDataForTab.$is(source.data)) setTabHovered(true);
      },
      onDragLeave: ({ source }) => {
        if (DragDataForTab.$is(source.data)) setTabHovered(false);
      },
      onDrop: () => setTabHovered(false),
    });
    onCleanup(() => cleanup());
  });

  return (
    <div
      ref={ref}
      class={cn("flex w-full h-full relative", layoutDirection[axis()])}
      data-split-panel-root
    >
      <Index each={props.split().children}>
        {(child, idx) => (
          <>
            <div
              class={cn("flex", layoutFullAxis[axis()])}
              style={{
                [layoutSize[axis()]]: `${child().percent * 100}%`,
              }}
            >
              <ViewPanelNode
                node={() => child().node}
                updateNode={(fn) =>
                  props.updateSplit((split) =>
                    PanelNode.Split({
                      ...split,
                      children: Array.modify(split.children, idx, (child) => ({
                        percent: child.percent,
                        node: fn(child.node),
                      })),
                    }),
                  )
                }
                parentSplitAxis={() => Option.some(axis())}
              />
            </div>

            <Show when={idx !== props.split().children.length - 1}>
              <SplitResizeHandle
                updateSplit={(fn) => props.updateSplit(fn)}
                currentChild={child}
                nextChild={() => props.split().children[idx + 1]}
                idx={() => idx}
                axis={() => props.split().axis}
              />
            </Show>
          </>
        )}
      </Index>

      <Show when={tabHovered()}>
        <SplitDropOverlay split={props.split} updateSplit={props.updateSplit} />
      </Show>
    </div>
  );
};

const SplitDropOverlay: Component<{
  split: () => PanelNode.Split;
  updateSplit: UpdateFn<PanelNode.Split>;
}> = (props) => {
  const axis = (): SplitAxis => props.split().axis;

  type DropInfo = {
    ref: HTMLDivElement | undefined;
    hovered: Accessor<boolean>;
    setHovered: Setter<boolean>;
    idx: Integer;
  };

  const sideInfos: Record<DropSide, DropInfo> = DropSide.reduce(
    (acc, side) => {
      const [hovered, setHovered] = createSignal(false);
      acc[side] = {
        ref: undefined,
        hovered,
        setHovered,
        idx: Match.value(side).pipe(
          Match.whenOr("left", "top", () => Integer(0)),
          Match.whenOr(
            "right",
            "bottom",
            // the state shouldn't change during a drag
            // eslint-disable-next-line solid/reactivity
            () => Integer(props.split().children.length),
          ),
          Match.exhaustive,
        ),
      };
      return acc;
    },
    {} as Record<DropSide, DropInfo>,
  );

  // the state shouldn't change during a drag
  // eslint-disable-next-line solid/reactivity
  const middleInfos: DropInfo[] = props.split().children.map((_, idx) => {
    const [hovered, setHovered] = createSignal(false);
    return {
      ref: undefined,
      hovered,
      setHovered,
      idx: Integer(idx + 1),
    };
  });

  onMount(() => {
    const cleanups: CleanupFn[] = [];

    const setupDropTarget = (info: DropInfo): void => {
      if (!info.ref) return;
      const cleanup = dropTargetForElements({
        element: info.ref,

        getData: () =>
          DropTargetSplitInsert({
            split: props.split(),
            updateSplit: props.updateSplit,
            idx: info.idx,
          }),

        canDrop: ({ source }) => {
          if (DragDataForTab.$is(source.data)) return true;
          return false;
        },

        onDragEnter: () => info.setHovered(true),
        onDragLeave: () => info.setHovered(false),
        onDrop: () => info.setHovered(false),
      });
      cleanups.push(cleanup);
    };

    for (const side of DropSide) {
      const info = sideInfos[side];
      setupDropTarget(info);
    }

    for (const info of middleInfos) {
      setupDropTarget(info);
    }

    onCleanup(() => {
      for (const cleanup of cleanups) cleanup();
    });
  });

  const sidePositions: Record<DropSide, string> = {
    left: "col-1 row-3",
    right: "col-5 row-3",
    top: "col-3 row-1",
    bottom: "col-3 row-5",
  };

  const sideIconsClass: Record<DropSide, string> = {
    left: "rotate-90",
    right: "-rotate-90",
    top: "rotate-180",
    bottom: "",
  };

  const RenderAppendDropPoint: Component<{ side: DropSide }> = (props) => {
    return (
      <RenderDropPoint
        ref={sideInfos[props.side].ref}
        icon="DndSplitAppend"
        tooltip={`append to split on ${props.side}`}
        hovered={sideInfos[props.side].hovered}
        class={sidePositions[props.side]}
        iconClass={sideIconsClass[props.side]}
      />
    );
  };

  const RenderInsertDropPoint: Component<{
    idx: number;
    style: JSX.CSSProperties;
  }> = (props) => {
    return (
      <RenderDropPoint
        ref={middleInfos[props.idx].ref}
        style={props.style}
        icon="DndSplitInsert"
        tooltip="insert tab in split"
        hovered={middleInfos[props.idx].hovered}
        class="absolute self-center z-50"
        iconClass={cn(axis() === "horizontal" ? "rotate-90" : "")}
      />
    );
  };

  return (
    <>
      <div
        class={cn(
          "absolute top-0 bottom-0 left-0 right-0 z-20",
          "grid",
          "grid-cols-[36px_1fr_36px_1fr_36px]",
          "grid-rows-[36px_1fr_36px_1fr_36px]",
          "pointer-events-none",
        )}
      >
        <Show when={axis() === "horizontal"}>
          <RenderAppendDropPoint side="left" />
          <RenderAppendDropPoint side="right" />
        </Show>
        <Show when={axis() === "vertical"}>
          <RenderAppendDropPoint side="top" />
          <RenderAppendDropPoint side="bottom" />
        </Show>
      </div>

      <For each={Array.range(0, props.split().children.length - 2)}>
        {(idx) => {
          // accumulate the sizes of children up to the current
          const percent = (): number => {
            let accum = 0;
            for (let i = 0; i <= idx; i += 1)
              accum += props.split().children[i].percent;
            assert(accum < 1);
            return accum;
          };

          return (
            <RenderInsertDropPoint
              idx={idx}
              style={{
                ...(axis() === "vertical"
                  ? {
                      top: `calc(${percent() * 100}% - 36px / 2`,
                    }
                  : {
                      left: `calc(${percent() * 100}% - 36px / 2`,
                    }),
              }}
            />
          );
        }}
      </For>
    </>
  );
};

export default ViewPanelNodeSplit;
