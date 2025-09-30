/* @refresh reload */
// dnd functionality breaks after a hmr, so a reload is needed anyway

import {
  Component,
  For,
  Index,
  onMount,
  ParentProps,
  Show,
  Switch,
  onCleanup,
  createSignal,
  batch,
  Setter,
  Accessor,
} from "solid-js";
import { render as solidRender } from "solid-js/web";
import { Option, Effect, Match, Order, pipe, Array } from "effect";
import { css } from "solid-styled-components";

import {
  draggable,
  dropTargetForElements,
  monitorForElements,
} from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { setCustomNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/set-custom-native-drag-preview";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { pointerOutsideOfPreview } from "@atlaskit/pragmatic-drag-and-drop/element/pointer-outside-of-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";
import { combine as pdndCombine } from "@atlaskit/pragmatic-drag-and-drop/combine";
import { CleanupFn } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";

import { Icon, IconKind, icons } from "~/assets/icons";

import { cn } from "~/lib/cn";
import Percent from "~/lib/Percent";
import { MatchTag } from "~/lib/MatchTag";
import assert from "~/lib/assert";
import Integer from "~/lib/Integer";
import { taggedCtor } from "~/lib/taggedCtor";

import { useWindowContext } from "~/ui/Window";
import Button from "~/ui/components/Button";

import { usePanelContext } from "./ContextProvider";
import {
  WorkspaceSidebars,
  WorkspaceSidebarSide,
  PanelNode,
  SplitAxis,
  SplitChild,
  Leaf,
  splitAddChild,
  tabsAddTab,
  sidebarToggle,
  splitUpdateChildPercent,
  tabsSelect,
} from "./data";

export type UpdateFn<T> = (fn: (_: T) => T) => void;

export const ViewRoot: Component = () => {
  onMount(() => {
    const cleanup = monitorForElements({
      onDrop: ({ source, location }) => {
        // @FIXME: we might need to check each drop target depending on how
        //   pdnd handles overlapping valid and invalid drop targets
        const destination = location.current.dropTargets[0];
        if (!destination) return;
        console.log("drop target count: ", location.current.dropTargets.length);

        const handleDragDataForTabOnDropTargetDataForTab = (
          drag: DragDataForTab,
          dropTarget: DropTargetDataForTab,
        ): void => {
          batch(() => {
            drag.updateTabs((tabs) =>
              PanelNode.Tabs({
                ...tabs,
                children: tabs.children.filter((_, idx) => idx !== drag.idx),
              }),
            );
            dropTarget.updateTabs((tabs) =>
              tabsAddTab({
                tabs,
                newLeaf: drag.node,
                idx: Option.getOrUndefined(dropTarget.idx),
              }).pipe(Effect.runSync),
            );
          });
        };

        const handleDragDataForTabOnDropTargetSplitInsert = (
          drag: DragDataForTab,
          dropTarget: DropTargetSplitInsert,
        ): void => {
          batch(() => {
            drag.updateTabs((tabs) =>
              PanelNode.Tabs({
                ...tabs,
                children: tabs.children.filter((_, idx) => idx !== drag.idx),
              }),
            );
            dropTarget.updateSplit((split) =>
              splitAddChild({
                split,
                child: PanelNode.makeTabs({
                  active: Integer(0),
                  children: [drag.node],
                }),
                idx: dropTarget.idx,
              }).pipe(Effect.runSync),
            );
          });
        };

        Match.value({
          source: source.data,
          destination: destination.data,
        }).pipe(
          Match.when(
            {
              source: (source) => DragDataForTab.$is(source),
              destination: (destination) =>
                DropTargetDataForTab.$is(destination),
            },
            ({ source, destination }) => {
              handleDragDataForTabOnDropTargetDataForTab(source, destination);
            },
          ),
          Match.when(
            {
              source: (source) => DragDataForTab.$is(source),
              destination: (destination) =>
                DropTargetSplitInsert.$is(destination),
            },
            ({ source, destination }) =>
              handleDragDataForTabOnDropTargetSplitInsert(source, destination),
          ),
          Match.orElse(() => {
            console.debug("no drop source/target pairs were matched");
          }),
        );
      },
    });
    onCleanup(() => cleanup());
  });

  return <ViewWorkspace />;
};

export const ViewPanelTitlebar: Component<
  ParentProps<{
    class?: string;
  }>
> = (props) => {
  let ref!: HTMLDivElement;
  return (
    <div data-panel-titlebar-root class={cn("min-h-6 max-h-6 relative")}>
      <div
        ref={ref}
        class={cn(
          "absolute left-0 right-0 top-0 bottom-0 flex flex-row items-center border-theme-border border-b overflow-x-scroll no-scrollbar",
          props.class,
        )}
        onWheel={(ev) => {
          // @HACK: This is real hacky, I find it hard to believe that there is
          //   no way to scroll horizontally by default on the web platform.
          //   Again this is a hack. I know at the native level it knows if it is
          //   discrete or not, so I hate having to check like this.
          //   Further on large lists, with multiple notches from a scroll wheel
          //   the scrollBy with smooth breaks and starts jittering
          //   The cleanest solution is to just have the `+=`s with the delta,
          //   only problem is that it it stops the smooth scroll.
          //   If we are so inclined, we could do so with a custom smooth scroll
          //   implementation, which may be needed for to be made other parts
          //   of the application.

          ev.preventDefault();

          const isDiscrete = Math.abs(ev.deltaY) < 50;

          if (isDiscrete) {
            ref.scrollLeft += ev.deltaY;
            ref.scrollLeft += ev.deltaX;
          } else {
            ref.scrollBy({ left: ev.deltaY, behavior: "smooth" });
          }
        }}
      >
        {props.children}
      </div>
    </div>
  );
};

export const ViewWorkspaceTitlebar: Component<{
  sidebars: () => WorkspaceSidebars;
}> = (props) => {
  const ctx = usePanelContext();

  type WindowButton = {
    icon: () => IconKind;
    onClick: () => void;
  };

  const windowCtx = useWindowContext();

  type WindowIconKind = "close" | "maximize" | "restore" | "minimize";
  type WindowIconRecord = Record<WindowIconKind, IconKind>;
  type WindowIcons = {
    record: WindowIconRecord;
    noDefaultStyles: boolean;
    class: string | undefined;
    iconClass: string | undefined;
  };

  const windowIcons = Match.value(window.api.platform).pipe(
    Match.withReturnType<WindowIcons>(),
    Match.when("Linux", () => ({
      record: {
        close: "adwaita_window_close",
        maximize: "adwaita_window_maximize",
        restore: "adwaita_window_restore",
        minimize: "adwaita_window_minimize",
      },
      class: "size-6 rounded-xl group hover:bg-transparent",
      iconClass:
        "stroke-theme-icon-base-transparent fill-theme-icon-base-stroke group-hover:bg-theme-icon-base-fill rounded-xl",
      noDefaultStyles: false,
    })),
    Match.orElse(() => ({
      record: {
        close: "close",
        maximize: "window_maximize",
        restore: "window_restore",
        minimize: "window_minimize",
      },
      class: "h-full w-10 rounded-none",
      iconClass: undefined,
      noDefaultStyles: false,
    })),
  );

  const windowButtons = (): WindowButton[] => [
    {
      icon: () => windowIcons.record.minimize,
      onClick: windowCtx.minimize,
    },
    {
      icon: () =>
        windowCtx.maximized()
          ? windowIcons.record.restore
          : windowIcons.record.maximize,
      onClick: windowCtx.toggleMaximize,
    },
    {
      icon: () => windowIcons.record.close,
      onClick: windowCtx.close,
    },
  ];

  return (
    <ViewPanelTitlebar class="window-drag gap-2 border-0">
      <Icon icon={icons["fe"]} noDefaultStyles class="size-4 mx-1" />

      <div class="flex flex-row h-full items-center gap-0.5 -window-drag">
        <Index
          each={[
            {
              class: "rotate-90",
              get: () => props.sidebars().left.enabled,
              toggle: () =>
                ctx.setWorkspace("sidebars", (sidebars) =>
                  sidebarToggle({ sidebars, side: "left" }).pipe(
                    Effect.runSync,
                  ),
                ),
            },
            {
              class: "",
              get: () => props.sidebars().bottom.enabled,
              toggle: () =>
                ctx.setWorkspace("sidebars", (sidebars) =>
                  sidebarToggle({ sidebars, side: "bottom" }).pipe(
                    Effect.runSync,
                  ),
                ),
            },
            {
              class: "-rotate-90",
              get: () => props.sidebars().right.enabled,
              toggle: () =>
                ctx.setWorkspace("sidebars", (sidebars) =>
                  sidebarToggle({ sidebars, side: "right" }).pipe(
                    Effect.runSync,
                  ),
                ),
            },
          ]}
        >
          {(bar) => (
            <Button
              as={Icon}
              icon={icons[bar().get() ? "sidebar_enabled" : "sidebar_disabled"]}
              class={cn("fill-transparent", bar().class)}
              size="icon"
              variant="icon"
              onClick={() => bar().toggle()}
            />
          )}
        </Index>
      </div>

      <div class="grow" />

      <div class="flex h-full -window-drag">
        <For each={windowButtons()}>
          {(button) => (
            <Button
              variant="icon"
              size="icon"
              class={windowIcons.class}
              noOnClickToOnMouseDown
              onClick={button.onClick}
            >
              <Icon
                icon={icons[button.icon()]}
                noDefaultStyles={windowIcons.noDefaultStyles}
                class={windowIcons.iconClass}
              />
            </Button>
          )}
        </For>
      </div>
    </ViewPanelTitlebar>
  );
};

export const ViewWorkspace: Component<{}> = () => {
  const ctx = usePanelContext();

  const sidebars = (): WorkspaceSidebars => ctx.workspace.sidebars;

  const sidebarSize = (side: WorkspaceSidebarSide): string =>
    `${sidebars()[side].size * 100}%`;

  const ViewSidebar: Component<{
    side: WorkspaceSidebarSide;
  }> = (props) => {
    const sizeType: Record<WorkspaceSidebarSide, "width" | "height"> = {
      left: "width",
      right: "width",
      bottom: "height",
    };

    const parentAxis: Record<WorkspaceSidebarSide, SplitAxis> = {
      left: "horizontal",
      right: "horizontal",
      bottom: "vertical",
    };

    return (
      <Show when={sidebars()[props.side].enabled}>
        <div
          data-sidebar-root
          data-sidebar-side={props.side}
          class="relative flex border-theme-border"
          style={{
            [sizeType[props.side]]: sidebarSize(props.side),
          }}
        >
          <ViewPanelNode
            node={() => sidebars()[props.side].node}
            updateNode={(fn) =>
              // false positive
              // eslint-disable-next-line solid/reactivity
              ctx.setWorkspace("sidebars", (sidebars) => ({
                ...sidebars,
                [props.side]: {
                  ...sidebars[props.side],
                  node: fn(sidebars[props.side].node),
                },
              }))
            }
            parentSplitAxis={() => Option.some(parentAxis[props.side])}
          />
        </div>
      </Show>
    );
  };

  const SidebarResizeHandle: Component<{
    side: WorkspaceSidebarSide;
  }> = (props) => {
    const axis: Record<WorkspaceSidebarSide, SplitAxis> = {
      left: "horizontal",
      right: "horizontal",
      bottom: "vertical",
    };
    const sign: Record<WorkspaceSidebarSide, "+" | "-"> = {
      left: "+",
      right: "-",
      bottom: "-",
    };

    return (
      <Show when={sidebars()[props.side].enabled}>
        <WorkspaceResizeHandle
          axis={axis[props.side]}
          size={sidebars()[props.side].size}
          updateSize={(size) =>
            // false positive
            // eslint-disable-next-line solid/reactivity
            ctx.setWorkspace("sidebars", (sidebars) => ({
              ...sidebars,
              [props.side]: {
                ...sidebars[props.side],
                size,
              },
            }))
          }
          sign={sign[props.side]}
        />
      </Show>
    );
  };

  return (
    <div class="flex flex-col w-full h-full" data-workspace-root>
      <ViewWorkspaceTitlebar sidebars={sidebars} />
      {/* border as an element to so you cannot drag the window by the border */}
      <div class="w-full min-h-[1px] max-h-[1px] bg-theme-border" />

      <div class="flex flex-row w-full h-full">
        <ViewSidebar side="left" />
        <SidebarResizeHandle side="left" />

        <div
          class="flex flex-col"
          style={{
            width: `${
              (1 -
                ((sidebars().left.enabled ? sidebars().left.size : 0) +
                  (sidebars().right.enabled ? sidebars().right.size : 0))) *
              100
            }%`,
          }}
        >
          <div
            class="flex w-full"
            style={{
              height: `${
                (1 - (sidebars().bottom.enabled ? sidebars().bottom.size : 0)) *
                100
              }%`,
            }}
          >
            <ViewPanelNode
              node={() => ctx.workspace.root}
              updateNode={(fn) => ctx.setWorkspace("root", fn)}
              parentSplitAxis={() => Option.none()}
            />
          </div>

          <SidebarResizeHandle side="bottom" />
          <ViewSidebar side="bottom" />
        </div>

        <SidebarResizeHandle side="right" />
        <ViewSidebar side="right" />
      </div>
    </div>
  );
};

export const ViewPanelNode: Component<{
  node: () => PanelNode;
  updateNode: UpdateFn<PanelNode>;
  parentSplitAxis: () => Option.Option<SplitAxis>;
}> = (props) => {
  return (
    <Switch>
      <MatchTag on={props.node()} tag={"Split"}>
        {(split) => (
          <ViewPanelNodeSplit
            split={split}
            updateSplit={(fn) =>
              props.updateNode((node) => {
                assert(PanelNode.$is("Split")(node));
                return fn(node);
              })
            }
          />
        )}
      </MatchTag>
      <MatchTag on={props.node()} tag={"Tabs"}>
        {(tabs) => (
          <ViewPanelNodeTabs
            tabs={tabs}
            updateTabs={(fn) =>
              props.updateNode((node) => {
                assert(PanelNode.$is("Tabs")(node));
                return fn(node);
              })
            }
            parentSplitAxis={props.parentSplitAxis}
          />
        )}
      </MatchTag>
    </Switch>
  );
};

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
        {(child, idx) => {
          return (
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
                        children: Array.modify(
                          split.children,
                          idx,
                          (child) => ({
                            percent: child.percent,
                            node: fn(child.node),
                          }),
                        ),
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
          );
        }}
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

  type SideInfo = {
    ref: HTMLDivElement | undefined;
    hovered: Accessor<boolean>;
    setHovered: Setter<boolean>;
    idx: Integer;
  };

  const Sides = ["left", "right", "top", "bottom"] as const;
  type Side = (typeof Sides)[number];

  const infos: Record<Side, SideInfo> = Sides.reduce(
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
    {} as Record<Side, SideInfo>,
  );

  onMount(() => {
    const cleanups: CleanupFn[] = [];

    for (const side of Sides) {
      const info = infos[side];

      if (!info.ref) continue;

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
    }

    onCleanup(() => {
      for (const cleanup of cleanups) cleanup();
    });
  });

  return (
    <>
      <div
        class={cn(
          "absolute top-0 bottom-0 left-0 right-0 z-10",
          "grid",
          "grid-cols-[2rem_1fr_3rem_1fr_2rem]",
          "grid-rows-[2rem_1fr_3rem_1fr_2rem]",
          "pointer-events-none",
        )}
      >
        <Show when={axis() === "vertical"}>
          {/* top */}
          <div
            ref={infos.top.ref}
            class={cn(
              "bg-green-400 pointer-events-auto",
              "col-3 row-1",
              infos.top.hovered() && "bg-green-400/20",
            )}
          />
          {/* bottom */}
          <div
            ref={infos.bottom.ref}
            class={cn(
              "bg-green-400 pointer-events-auto",
              "col-3 row-5",
              infos.bottom.hovered() && "bg-green-400/20",
            )}
          />
        </Show>
        <Show when={axis() === "horizontal"}>
          {/* left */}
          <div
            ref={infos.left.ref}
            class={cn(
              "bg-green-400 pointer-events-auto",
              "col-1 row-3",
              infos.left.hovered() && "bg-green-400/20",
            )}
          />
          {/* right */}
          <div
            ref={infos.right.ref}
            class={cn(
              "bg-green-400 pointer-events-auto",
              "col-5 row-3",
              infos.right.hovered() && "bg-green-400/20",
            )}
          />
        </Show>
      </div>

      <For each={props.split().children}>
        {(_, idx) => {
          // accumulate the sizes of children up to the current
          const percent = (): number => {
            let accum = 0;
            for (let i = 0; i <= idx(); i += 1)
              accum += props.split().children[i].percent;
            assert(accum < 1);
            return accum;
          };

          return (
            <Show when={idx() !== props.split().children.length - 1}>
              <div
                class={cn("absolute bg-purple-600 self-center")}
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
      </For>
    </>
  );
};

const SplitResizeHandle: Component<{
  updateSplit: UpdateFn<PanelNode.Split>;
  currentChild: () => SplitChild;
  nextChild: () => SplitChild;
  idx: () => number;
  axis: () => SplitAxis;
}> = (props) => {
  const ctx = usePanelContext();

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

  return (
    <ResizeHandleRender ref={ref} axis={props.axis()} resizing={resizing} />
  );
};

const WorkspaceResizeHandle: Component<{
  axis: SplitAxis;
  size: Percent;
  updateSize: (size: Percent) => void;
  sign: "+" | "-";
}> = (props) => {
  const ctx = usePanelContext();

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

  return <ResizeHandleRender ref={ref} axis={props.axis} resizing={resizing} />;
};

export const ResizeHandleRender: Component<{
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

export const ViewPanelNodeTabs: Component<{
  tabs: () => PanelNode.Tabs;
  updateTabs: UpdateFn<PanelNode.Tabs>;
  parentSplitAxis: () => Option.Option<SplitAxis>;
}> = (props) => {
  const ctx = usePanelContext();

  const active = (): Option.Option<Leaf> =>
    // false positive
    // eslint-disable-next-line solid/reactivity
    Option.flatMap(props.tabs().active, (idx) => {
      if (idx >= props.tabs().children.length) return Option.none();
      return Option.some(props.tabs().children[idx]);
    });

  const [hasDrop, setHasDrop] = createSignal(false);

  let tabDropRef!: HTMLDivElement;
  onMount(() => {
    const cleanup = dropTargetForElements({
      element: tabDropRef,

      getData: () =>
        DropTargetDataForTab({
          tabs: props.tabs(),
          updateTabs: props.updateTabs,
          idx: Option.none(),
        }),

      canDrop: ({ source }) => {
        if (DragDataForTab.$is(source.data)) return true;

        return false;
      },

      onDragEnter: () => setHasDrop(true),
      onDragLeave: () => setHasDrop(false),
      onDrop: () => setHasDrop(false),
    });
    onCleanup(() => cleanup());
  });

  const activeTabContent = (): Component<{}> =>
    active().pipe(
      Option.flatMap(({ id }) =>
        ctx.getLeaf(id).pipe(Option.map((content) => content.render)),
      ),
      Option.getOrElse(() => () => (
        <div class="flex w-full h-full items-center justify-center">
          <p>no tab selected</p>
        </div>
      )),
    );

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
      class="flex flex-col relative w-full h-full"
      data-tabs-panel-root
    >
      <ViewPanelTitlebar class="px-1">
        <For each={props.tabs().children}>
          {(child, idx) => (
            <ViewTabHandle
              tabs={props.tabs}
              updateTabs={props.updateTabs}
              active={() => props.tabs().active}
              idx={() => Integer(idx())}
              leaf={() => child}
              onClick={() => {
                // false positive
                // eslint-disable-next-line solid/reactivity
                props.updateTabs((tabs) => {
                  return tabsSelect({
                    tabs,
                    index: Option.some(Integer(idx())),
                  }).pipe(Effect.runSync);
                });
              }}
              onCloseClick={() => {
                console.warn("TODO: tab close click");
              }}
            />
          )}
        </For>

        <div
          ref={tabDropRef}
          class={cn(
            "grow h-full min-w-5",
            hasDrop() && "bg-theme-panel-tab-background-drop-target",
          )}
          onClick={() =>
            props.updateTabs((tabs) =>
              tabsSelect({
                tabs,
                index: Option.none(),
              }).pipe(Effect.runSync),
            )
          }
        />

        <div class="flex items-center border-l border-theme-border h-full">
          <Button
            as={Icon}
            icon={icons["add"]}
            variant="icon"
            size="icon"
            class="p-1 ml-1"
            onClick={() => {
              console.warn("TODO: new tab");
            }}
          />
        </div>
      </ViewPanelTitlebar>

      <ViewPanelNodeLeafContent render={() => activeTabContent()} />

      <Show when={tabHovered()}>
        <TabsDropOverlay parentSplitAxis={props.parentSplitAxis} />
      </Show>
    </div>
  );
};

const TabsDropOverlay: Component<{
  parentSplitAxis: () => Option.Option<SplitAxis>;
}> = (props) => {
  return (
    <div
      class={cn(
        "absolute top-0 bottom-0 left-0 right-0 z-10",
        "grid",
        "grid-cols-[1fr_3rem_3rem_3rem_1fr]",
        "grid-rows-[1fr_3rem_3rem_3rem_1fr]",
        "pointer-events-none",
      )}
    >
      {/* center */}
      <div class={cn("bg-orange-400 pointer-events-auto", "col-3 row-3")} />

      <Show
        when={
          props
            .parentSplitAxis()
            .pipe(Option.getOrElse<SplitAxis>(() => "vertical")) === "vertical"
        }
      >
        {/* left */}
        <div class={cn("bg-blue-900 pointer-events-auto", "col-2 row-3")} />
        {/* right */}
        <div class={cn("bg-blue-900 pointer-events-auto", "col-4 row-3")} />
      </Show>
      <Show
        when={
          props
            .parentSplitAxis()
            .pipe(Option.getOrElse<SplitAxis>(() => "horizontal")) ===
          "horizontal"
        }
      >
        {/* top */}
        <div class={cn("bg-blue-900 pointer-events-auto", "col-3 row-2")} />
        {/* bottom */}
        <div class={cn("bg-blue-900 pointer-events-auto", "col-3 row-4")} />
      </Show>
    </div>
  );
};

export const ViewTabHandle: Component<{
  tabs: () => PanelNode.Tabs;
  updateTabs: UpdateFn<PanelNode.Tabs>;
  active: () => Option.Option<Integer>;
  idx: () => Integer;
  leaf: () => Leaf;
  onClick: () => void;
  onCloseClick: () => void;
}> = (props) => {
  const ctx = usePanelContext();

  const selected = (): boolean =>
    // false positive
    // eslint-disable-next-line solid/reactivity
    Option.map(props.active(), (i) => i === props.idx()).pipe(
      Option.getOrElse(() => false),
    );

  const [dragging, setDragging] = createSignal(false);
  const [hasDrop, setHasDrop] = createSignal(false);

  const title = (): string =>
    Option.getOrElse(
      Option.map(ctx.getLeaf(props.leaf().id), (leaf) => leaf.title),
      () => "<none leaf>",
    );

  let ref!: HTMLDivElement;
  onMount(() => {
    const cleanup = pdndCombine(
      draggable({
        element: ref,

        getInitialData: () =>
          DragDataForTab({
            tabs: props.tabs(),
            updateTabs: props.updateTabs,
            node: props.leaf(),
            idx: props.idx(),
          }),

        onGenerateDragPreview: ({ nativeSetDragImage }) => {
          setDragging(true);

          setCustomNativeDragPreview({
            getOffset: pointerOutsideOfPreview({
              x: "calc(var(--spacing) * 2)",
              y: "calc(var(--spacing) * 2)",
            }),
            render: ({ container }) =>
              solidRender(
                () => (
                  <ViewTabHandleImpl
                    class="h-6 border text-theme-text bg-theme-background"
                    title={title}
                  />
                ),
                container,
              ),
            nativeSetDragImage,
          });
        },
        onDrop: () => setDragging(false),
      }),
      dropTargetForElements({
        element: ref,

        getData: () =>
          DropTargetDataForTab({
            tabs: props.tabs(),
            updateTabs: props.updateTabs,
            idx: Option.some(props.idx()),
          }),

        canDrop: ({ source }) => {
          if (DragDataForTab.$is(source.data)) return true;

          return false;
        },

        onDragEnter: () => setHasDrop(true),
        onDragLeave: () => setHasDrop(false),
        onDrop: () => setHasDrop(false),
      }),
    );
    onCleanup(() => cleanup());
  });

  return (
    <ViewTabHandleImpl
      ref={ref}
      class={cn(
        "relative first:border-l border-r cursor-pointer hover:bg-theme-panel-tab-background-active transition-colors duration-100",
        selected() && "bg-theme-panel-tab-background-active",
        dragging() && "text-transparent",
        hasDrop() && "bg-theme-panel-tab-background-drop-target",
      )}
      title={title}
      onClick={() => {
        if (selected()) return;
        props.onClick();
      }}
      onCloseClick={props.onCloseClick}
    />
  );
};

const ViewTabHandleImpl: Component<{
  ref?: HTMLDivElement;
  class?: string;
  title: () => string;
  onClick?: () => void;
  onCloseClick?: () => void;
}> = (props) => {
  return (
    <div
      ref={props.ref}
      class={cn(
        "flex items-center h-full pt-0.5 px-0.5 gap-0.5 border-theme-border text-sm bg-theme-panel-tab-background-idle group overflow-clip whitespace-nowrap",
        props.class,
      )}
      onClick={() => props.onClick?.()}
    >
      {/* icon placeholder */}
      <div class="size-3.5" />

      {props.title()}

      <Button
        as={Icon}
        icon={icons["close"]}
        variant="icon"
        size="icon"
        class="size-3.5 mb-0.5 opacity-0 group-hover:opacity-100"
        noOnClickToOnMouseDown
        onClick={(event) => {
          if (!props.onCloseClick) return;
          event.stopPropagation();
          props.onCloseClick();
        }}
      />
    </div>
  );
};

export const ViewPanelNodeLeafContent: Component<{
  render: () => Component<{}>;
}> = (props) => {
  return (
    <div class="flex relative w-full h-full" data-panel-leaf-content-root>
      {/* using absolute is the only way I have found to completely ensure that
          the rendered content cannot affect the outside sizing - breaking the
          whole panel layout system */}
      <div class="absolute left-0 right-0 top-0 bottom-0 overflow-auto">
        {props.render()({})}
      </div>
    </div>
  );
};

export type DragDataForTab = Readonly<{
  _tag: "DragDataForTab";
  tabs: PanelNode.Tabs;
  updateTabs: UpdateFn<PanelNode.Tabs>;
  node: Leaf;
  idx: Integer;
}>;
export const DragDataForTab = taggedCtor<DragDataForTab>("DragDataForTab");

export type DropTargetDataForTab = Readonly<{
  _tag: "DropTargetDataForTab";
  tabs: PanelNode.Tabs;
  updateTabs: UpdateFn<PanelNode.Tabs>;
  idx: Option.Option<Integer>;
}>;
export const DropTargetDataForTab = taggedCtor<DropTargetDataForTab>(
  "DropTargetDataForTab",
);

export type DropTargetSplitInsert = Readonly<{
  _tag: "DropTargetSplitInsert";
  split: PanelNode.Split;
  updateSplit: UpdateFn<PanelNode.Split>;
  idx: Integer;
}>;
export const DropTargetSplitInsert = taggedCtor<DropTargetSplitInsert>(
  "DropTargetSplitInsert",
);

export namespace View {
  export const Root = ViewRoot;
  export const PanelTitlebar = ViewPanelTitlebar;
  export const WorkspaceTitlebar = ViewWorkspaceTitlebar;
  export const Workspace = ViewWorkspace;
  export const PanelNode = ViewPanelNode;
  export const PanelNodeSplit = ViewPanelNodeSplit;
  export const PanelNodeTabs = ViewPanelNodeTabs;
  export const TabHandle = ViewTabHandle;
  // export const PanelNodeLeaf = ViewPanelNodeLeaf;
  export const PanelNodeLeafContent = ViewPanelNodeLeafContent;
}
export default View;
