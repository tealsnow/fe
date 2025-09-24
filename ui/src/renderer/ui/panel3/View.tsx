import {
  Component,
  createEffect,
  For,
  Index,
  onMount,
  ParentProps,
  Show,
  Switch,
  onCleanup,
  createSignal,
} from "solid-js";
import { Option, Effect, Match, Order, pipe, Equal } from "effect";
import { MapOption } from "solid-effect";
import { css } from "solid-styled-components";

import {
  draggable,
  // dropTargetForElements,
  // monitorForElements,
} from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
// import { setCustomNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/set-custom-native-drag-preview";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
// import { pointerOutsideOfPreview } from "@atlaskit/pragmatic-drag-and-drop/element/pointer-outside-of-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";
// import { combine as pdndCombine } from "@atlaskit/pragmatic-drag-and-drop/combine";
// import { CleanupFn } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";
// import { GetOffsetFn } from "@atlaskit/pragmatic-drag-and-drop/dist/types/public-utils/element/custom-native-drag-preview/types";

import { Icon, IconKind, icons } from "~/assets/icons";

import { cn } from "~/lib/cn";
import Percent from "~/lib/Percent";
import { MatchTag } from "~/lib/MatchTag";
import assert from "~/lib/assert";
import Integer from "~/lib/Integer";

import { useWindowContext } from "~/ui/WindowContext";
import Button from "~/ui/components/Button";

import { usePanelContext } from "./Context";
import {
  toggleSidebar,
  WorkspaceSidebars,
  WorkspaceSidebarSide,
  PanelNode,
  LeafContent,
  selectTab,
  SplitAxis,
  updateSplitChildPercent,
  SplitChild,
  updateNode,
} from "./data";

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
      <div class="w-full h-[1px] bg-theme-border" />

      <div class="flex flex-row grow">
        <ViewSidebar side="left" />
        <SidebarHandle side="left" />

        <div class="flex flex-col grow">
          <div class="flex grow">
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

  return (
    <div class="flex flex-col grow overflow-none">
      <ViewPanelTitlebar class="px-1">
        <For each={props.tabs().children}>
          {(child, idx) => {
            const title = (): string => ctx.getLeafContent(child.id).title;

            const selected = (): boolean =>
              // false positive
              // eslint-disable-next-line solid/reactivity
              Option.map(props.tabs().active, (i) => i === idx()).pipe(
                Option.getOrElse(() => false),
              );

            return (
              <div
                class={cn(
                  "flex items-center h-full pt-0.5 px-0.5 gap-0.5 border-theme-border border-l last:border-r text-sm group cursor-pointer bg-theme-panel-tab-background-idle hover:bg-theme-panel-tab-background-active",
                  selected() && "bg-theme-panel-tab-background-active",
                )}
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
              >
                {/* icon placeholder */}
                <div class="size-3.5" />

                {title()}

                <Button
                  as={Icon}
                  icon={icons["close"]}
                  variant="icon"
                  size="icon"
                  class="size-3.5 mb-0.5 opacity-0 group-hover:opacity-100"
                  noOnClickToOnMouseDown
                  onClick={() => {
                    // close tab
                  }}
                />
              </div>
            );
          }}
        </For>
      </ViewPanelTitlebar>
      <MapOption on={active()}>
        {(tab) => {
          const content = (): LeafContent => ctx.getLeafContent(tab().id);
          return <ViewPanelNodeLeafContent content={content} />;
        }}
      </MapOption>
    </div>
  );
};

export const ViewPanelNodeLeaf: Component<{
  leaf: () => PanelNode.Leaf;
}> = (props) => {
  const ctx = usePanelContext();

  const content = (): LeafContent => ctx.getLeafContent(props.leaf().id);

  return (
    <div class="flex flex-col grow overflow-none">
      <ViewPanelTitlebar class="text-sm px-1">
        {/* if someone can tell how the fuck overflow and/or ellipses are meant
            to work in css I'd really fucking appreciate it
            I've tried every combination of css under the sun,
            but it just never fucking works, google's useless */}
        {content().title}
      </ViewPanelTitlebar>
      <ViewPanelNodeLeafContent content={content} />
    </div>
  );
};

export const ViewPanelNodeLeafContent: Component<{
  content: () => LeafContent;
}> = (props) => {
  return (
    <div class="flex grow overflow-auto">{props.content().render({})}</div>
  );
};

export namespace View {
  export const PanelTitlebar = ViewPanelTitlebar;
  export const Workspace = ViewWorkspace;
  export const PanelNode = ViewPanelNode;
  export const PanelNodeSplit = ViewPanelNodeSplit;
  export const PanelNodeTabs = ViewPanelNodeTabs;
  export const PanelNodeLeaf = ViewPanelNodeTabs;
}
export default View;
