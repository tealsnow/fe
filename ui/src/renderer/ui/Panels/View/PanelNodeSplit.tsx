import {
  Component,
  Index,
  onMount,
  Show,
  onCleanup,
  createSignal,
  Setter,
  Accessor,
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
              class={cn("flex border-theme-border", layoutFullAxis[axis()])}
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

  return (
    <>
      <div
        class={cn(
          "absolute top-0 bottom-0 left-0 right-0 z-20",
          "grid",
          "grid-cols-[2rem_1fr_3rem_1fr_2rem]",
          "grid-rows-[2rem_1fr_3rem_1fr_2rem]",
          "pointer-events-none",
        )}
      >
        <Show when={axis() === "vertical"}>
          {/* top */}
          <div
            ref={sideInfos.top.ref}
            class={cn(
              "bg-green-400 pointer-events-auto",
              "col-3 row-1",
              sideInfos.top.hovered() && "bg-green-400/20",
            )}
          />
          {/* bottom */}
          <div
            ref={sideInfos.bottom.ref}
            class={cn(
              "bg-green-400 pointer-events-auto",
              "col-3 row-5",
              sideInfos.bottom.hovered() && "bg-green-400/20",
            )}
          />
        </Show>
        <Show when={axis() === "horizontal"}>
          {/* left */}
          <div
            ref={sideInfos.left.ref}
            class={cn(
              "bg-green-400 pointer-events-auto",
              "col-1 row-3",
              sideInfos.left.hovered() && "bg-green-400/20",
            )}
          />
          {/* right */}
          <div
            ref={sideInfos.right.ref}
            class={cn(
              "bg-green-400 pointer-events-auto",
              "col-5 row-3",
              sideInfos.right.hovered() && "bg-green-400/20",
            )}
          />
        </Show>
      </div>

      <Index each={props.split().children}>
        {(_, idx) => {
          // accumulate the sizes of children up to the current
          const percent = (): number => {
            let accum = 0;
            for (let i = 0; i <= idx; i += 1)
              accum += props.split().children[i].percent;
            assert(accum < 1);
            return accum;
          };

          const info = (): DropInfo => middleInfos[idx];

          return (
            <Show when={idx !== props.split().children.length - 1}>
              <div
                ref={info().ref}
                class={cn(
                  "absolute bg-purple-600 self-center z-20",
                  info().hovered() && "bg-purple-600/20",
                )}
                style={{
                  ...(axis() === "vertical"
                    ? {
                        width: "3rem",
                        height: "2rem",
                        top: `calc(${percent() * 100}% - 2rem / 2`,
                      }
                    : {
                        width: "2rem",
                        height: "3rem",
                        left: `calc(${percent() * 100}% - 2rem / 2`,
                      }),
                }}
              />
            </Show>
          );
        }}
      </Index>
    </>
  );
};

export default ViewPanelNodeSplit;
