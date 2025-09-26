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
} from "solid-js";
import { render as solidRender } from "solid-js/web";
import { Option, Effect, Match, Order, pipe, Equal } from "effect";
import { MapOption } from "solid-effect";
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
// import { CleanupFn } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";
import { GetOffsetFn } from "@atlaskit/pragmatic-drag-and-drop/dist/types/public-utils/element/custom-native-drag-preview/types";

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
  toggleSidebar,
  WorkspaceSidebars,
  WorkspaceSidebarSide,
  PanelNode,
  selectTab,
  SplitAxis,
  updateSplitChildPercent,
  SplitChild,
  updateNode,
  removeChild,
  addTab,
} from "./data";

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
            drag.updateParent((parent) =>
              removeChild({
                parent,
                match: (node) => Equal.equals(node, drag.node),
              }).pipe(
                Effect.catchTag("NodeNotFoundError", (err) => {
                  console.error(
                    "failed to find child in what is meant to be its parent",
                    err,
                  );
                  return Effect.sync(() => parent);
                }),
                Effect.runSync,
              ),
            );

            dropTarget.updateTabs((tabs) => {
              return addTab({
                tabs,
                newLeaf: drag.node,
                idx: Option.getOrUndefined(dropTarget.idx),
              }).pipe(Effect.runSync);
            });
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
  return (
    <div
      class={cn(
        "flex flex-row min-h-6 max-h-6 w-full items-center border-theme-border border-b",
        props.class,
      )}
    >
      {props.children}
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
                  toggleSidebar({ sidebars, side: "left" }).pipe(
                    Effect.runSync,
                  ),
                ),
            },
            {
              class: "",
              get: () => props.sidebars().bottom.enabled,
              toggle: () =>
                ctx.setWorkspace("sidebars", (sidebars) =>
                  toggleSidebar({ sidebars, side: "bottom" }).pipe(
                    Effect.runSync,
                  ),
                ),
            },
            {
              class: "-rotate-90",
              get: () => props.sidebars().right.enabled,
              toggle: () =>
                ctx.setWorkspace("sidebars", (sidebars) =>
                  toggleSidebar({ sidebars, side: "right" }).pipe(
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

    return (
      <Show when={sidebars()[props.side].enabled}>
        <div
          class="relative flex border-theme-border overflow-none"
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
          />
        </div>
      </Show>
    );
  };

  const SidebarHandle: Component<{
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
    <div class="flex flex-col grow">
      <ViewWorkspaceTitlebar sidebars={sidebars} />
      {/* border as an element to so you cannot drag the window by the border */}
      <div class="w-full min-h-[1px] max-h-[1px] bg-theme-border" />

      <div class="flex flex-row grow">
        <ViewSidebar side="left" />
        <SidebarHandle side="left" />

        <div class="flex flex-col grow">
          <div
            class="flex"
            style={{
              height: `${
                sidebars().bottom.enabled
                  ? (1 - sidebars().bottom.size) * 100
                  : 100
              }%`,
              width: `${
                1 -
                ((sidebars().left.enabled ? sidebars().left.size : 0) +
                  (sidebars().right.enabled ? sidebars().right.size : 0)) *
                  100
              }%`,
            }}
          >
            <ViewPanelNode
              node={() => ctx.workspace.root}
              updateNode={(fn) => ctx.setWorkspace("root", fn)}
            />
          </div>

          <SidebarHandle side="bottom" />
          <ViewSidebar side="bottom" />
        </div>

        <SidebarHandle side="right" />
        <ViewSidebar side="right" />
      </div>
    </div>
  );
};

export const ViewPanelNode: Component<{
  node: () => PanelNode;
  updateNode: (fn: (node: PanelNode) => PanelNode) => void;
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
          />
        )}
      </MatchTag>
      <MatchTag on={props.node()} tag={"Leaf"}>
        {(leaf) => <ViewPanelNodeLeaf leaf={leaf} />}
      </MatchTag>
    </Switch>
  );
};

export const ViewPanelNodeSplit: Component<{
  split: () => PanelNode.Split;
  updateSplit: (fn: (split: PanelNode.Split) => PanelNode.Split) => void;
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

  return (
    <div class={cn("flex grow", layoutDirection[axis()])}>
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
                    props.updateSplit((split) => {
                      const res = updateNode({
                        node: split,
                        match: (node) => Equal.equals(node, child().node),
                        fn,
                      }).pipe(Effect.runSync);
                      assert(PanelNode.$is("Split")(res));
                      return res;
                    })
                  }
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
    </div>
  );
};

const SplitResizeHandle: Component<{
  updateSplit: (fn: (split: PanelNode.Split) => PanelNode.Split) => void;
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
        props.updateSplit((split) => {
          return pipe(
            updateSplitChildPercent({
              split,
              childIndex: Integer(props.idx()),
              percent: Percent(newCurrentPercent),
            }),
            Effect.flatMap((split) =>
              updateSplitChildPercent({
                split,
                childIndex: Integer(props.idx() + 1),
                percent: Percent(newNextPercent),
              }),
            ),
            Effect.catchTag("OutOfBoundsError", (err) => {
              console.error(
                "Split child index out of bounds when trying to resize split.",
                err,
              );
              return Effect.sync(() => split);
            }),
            Effect.runSync,
          );
        });
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
        "relative bg-theme-border transition-colors hover:bg-theme-deemphasis",
        axisStyles[props.axis],
        props.resizing() && "bg-theme-deemphasis",
        css`
          &::before {
            content: "";
            position: absolute;
            ${pseudoStyles[props.axis]}
          }
        `,
      )}
    />
  );
};

export const ViewPanelNodeTabs: Component<{
  tabs: () => PanelNode.Tabs;
  updateTabs: (fn: (tabs: PanelNode.Tabs) => PanelNode.Tabs) => void;
}> = (props) => {
  const ctx = usePanelContext();

  const active = (): Option.Option<PanelNode.Leaf> =>
    // false positive
    // eslint-disable-next-line solid/reactivity
    Option.map(props.tabs().active, (idx) => props.tabs().children[idx]);

  // const updateParent = (
  //   fn: (node: PanelNode.Tabs) => PanelNode.Tabs,
  // ): void => {
  //   props.updateTabs(fn);
  // };

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

  return (
    <div class="flex flex-col grow overflow-none">
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
                  return selectTab({
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
            "grow h-full",
            hasDrop() && "bg-theme-panel-tab-background-drop-target",
          )}
        />
      </ViewPanelTitlebar>
      <MapOption
        on={active()}
        fallback={
          <div class="flex grow items-center justify-center">
            <p>no tab selected</p>
          </div>
        }
      >
        {(leaf) => {
          return (
            <MapOption
              on={ctx.getLeaf(leaf().id)}
              fallback={
                <div class="flex grow items-center justify-center">
                  <p>TODO: none leaf in tabs</p>
                </div>
              }
            >
              {(content) => (
                <ViewPanelNodeLeafContent render={() => content().render} />
              )}
            </MapOption>
          );
        }}
      </MapOption>
    </div>
  );
};

export const ViewTabHandle: Component<{
  tabs: () => PanelNode.Tabs;
  updateTabs: (fn: (tabs: PanelNode.Tabs) => PanelNode.Tabs) => void;
  active: () => Option.Option<Integer>;
  idx: () => Integer;
  leaf: () => PanelNode.Leaf;
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
            parent: props.tabs(),
            updateParent: (fn) =>
              props.updateTabs((parent) => {
                const node = fn(parent);
                assert(PanelNode.$is("Tabs")(node));
                return node;
              }),
            node: props.leaf(),
            idx: props.idx(),
          }),

        onGenerateDragPreview: ({ nativeSetDragImage }) => {
          setDragging(true);

          setCustomNativeDragPreview({
            getOffset: tabNativeDragPreviewOffset(),
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
        "relative first:border-l border-r cursor-pointer hover:bg-theme-panel-tab-background-active",
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
        "flex items-center h-full pt-0.5 px-0.5 gap-0.5 border-theme-border text-sm bg-theme-panel-tab-background-idle group",
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

const tabNativeDragPreviewOffset = (): GetOffsetFn =>
  pointerOutsideOfPreview({
    x: "calc(var(--spacing) * 2)",
    y: "calc(var(--spacing) * 2)",
  });

export const ViewPanelNodeLeaf: Component<{
  leaf: () => PanelNode.Leaf;
}> = (props) => {
  const ctx = usePanelContext();

  return (
    <MapOption
      on={ctx.getLeaf(props.leaf().id)}
      fallback={
        <div class="flex grow items-center justify-center">
          <p>TODO: none leaf</p>
        </div>
      }
    >
      {(content) => (
        <div class="flex flex-col grow overflow-none">
          <ViewPanelTitlebar class="text-sm relative overflow-none">
            {/* I've never liked css, but this is just insane.
                Just makes me like tailwind more for what it does do */}
            <p class="absolute left-0 right-0 overflow-clip text-ellipsis whitespace-nowrap px-1">
              {content().title}
            </p>
          </ViewPanelTitlebar>
          <ViewPanelNodeLeafContent render={() => content().render} />
        </div>
      )}
    </MapOption>
  );
};

export const ViewPanelNodeLeafContent: Component<{
  render: () => Component<{}>;
}> = (props) => {
  return (
    <div class="flex grow relative overflow-none">
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
  parent: PanelNode.Parent;
  updateParent: (fn: (parent: PanelNode.Parent) => PanelNode.Parent) => void;
  node: PanelNode.Leaf;
  idx: Integer;
}>;
export const DragDataForTab = taggedCtor<DragDataForTab>("DragDataForTab");

export type DropTargetDataForTab = Readonly<{
  _tag: "DropTargetDataForTab";
  tabs: PanelNode.Tabs;
  updateTabs: (fn: (tabs: PanelNode.Tabs) => PanelNode.Tabs) => void;
  idx: Option.Option<Integer>;
}>;
export const DropTargetDataForTab = taggedCtor<DropTargetDataForTab>(
  "DropTargetDataForTab",
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
  export const PanelNodeLeaf = ViewPanelNodeLeaf;
  export const PanelNodeLeafContent = ViewPanelNodeLeafContent;
}
export default View;
