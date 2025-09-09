import {
  createMemo,
  createSignal,
  For,
  Match,
  onCleanup,
  onMount,
  Show,
  Switch,
} from "solid-js";
import { css } from "solid-styled-components";
import { MapOption } from "solid-effect";

import { Brand, Effect, Option, Order } from "effect";

import {
  draggable,
  dropTargetForElements,
  monitorForElements,
} from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";

import { cn } from "~/lib/cn";
import assert from "~/lib/assert";
import { MatchTag } from "~/lib/MatchTag";

import Button from "~/ui/components/Button";
import { Icon } from "~/assets/icons";

import * as Panel from "./Panel";

export type RenderPanelsProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;
  selectedPanel: () => Option.Option<Panel.ID>;
  selectPanel: (id: Panel.ID) => void;
  dbgHeader: () => boolean;
};

export const RenderPanels = (props: RenderPanelsProps) => {
  onMount(() => {
    // orchestrates the whole dnd system
    // has access to both "source" and "destination"
    // handles the actual drop and state update
    const cleanup = monitorForElements({
      onDrop: ({ source, location }) => {
        // @FIXME: we might need to check each drop target depending on how
        //   pdnd handles overlapping valid and invalid drop targets
        const destination = location.current.dropTargets[0];
        if (!destination) return;
        if (isTabHandleDragData(source.data)) {
          // we have a tab to drop
          const sourceTabHandleData = source.data;
          if (isTabBarDropData(destination.data)) {
            // we are dropping a tab on a tab bar
            const dropTabBarData = destination.data;

            // @NOTE: this does, in fact, work for the case when the source
            //   and destination parents are the same - it puts it to the last in the list
            Panel.Node.reParent(props.setTree, {
              id: sourceTabHandleData.panel,
              newParentId: dropTabBarData.parent,
            }).pipe(Effect.runSync);
            return;
          }

          // @TODO: drop on another tab for reordering
          // @TODO: drop zones within panels for tree manipulation
        }
      },
    });
    onCleanup(() => cleanup());
  });

  return (
    <RenderPanel
      tree={props.tree}
      setTree={props.setTree}
      parentLayout="vertical"
      panelId={() => props.tree.root}
      selectPanel={props.selectPanel}
      selectedPanel={props.selectedPanel}
      dbgHeader={props.dbgHeader}
    />
  );
};

export type RenderPanelProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;
  parentLayout: Panel.Layout;
  panelId: () => Panel.ID;
  selectedPanel: () => Option.Option<Panel.ID>;
  selectPanel: (id: Panel.ID) => void;
  dbgHeader: () => boolean;
};

export const RenderPanel = (props: RenderPanelProps) => {
  const panel = createMemo(() =>
    Panel.Node.getOrError(props.tree, { id: props.panelId() }) //
      .pipe(Effect.runSync),
  );

  const isSelected = () =>
    Option.getOrNull(props.selectedPanel()) === panel().id;

  return (
    <div
      class={cn(
        "flex flex-col w-full h-full outline-theme-colors-purple-border/80 -outline-offset-1",
        isSelected() && "outline",
      )}
      style={
        props.parentLayout === "vertical"
          ? {
              width: "100%",
              height: panel().percentOfParent * 100 + "%",
            }
          : {
              height: "100%",
              width: panel().percentOfParent * 100 + "%",
            }
      }
    >
      <Show when={props.dbgHeader()}>
        <div class="flex flex-row w-full h-fit p-0.5 gap-1 items-center border border-theme-colors-orange-border overflow-clip">
          <Button
            color="orange"
            size="small"
            highlighted={isSelected()}
            onClick={() => props.selectPanel(panel().id)}
          >
            {panel().id.uuid}
            <MapOption on={Panel.Node.$as("leaf")(panel())}>
              {(leaf) => <> - '{leaf().title}'</>}
            </MapOption>
          </Button>
        </div>
      </Show>

      <Switch>
        <MatchTag on={panel()} tag="leaf">
          {(_leaf) => <div class="w-full h-full">{/* content */}</div>}
        </MatchTag>
        <MatchTag on={panel()} tag="parent">
          {(parent) => (
            <Switch>
              <Match when={parent().layout === "tabs"}>
                <TabBar
                  tree={props.tree}
                  setTree={props.setTree}
                  parent={parent}
                />
              </Match>
              <Match when={parent().layout !== "tabs"}>
                <div
                  class={cn(
                    "flex w-full h-full",
                    parent().layout === "vertical" ? "flex-col" : "flex-row",
                  )}
                >
                  <For each={parent().children}>
                    {(panelId, idx) => (
                      <>
                        <RenderPanel
                          tree={props.tree}
                          setTree={props.setTree}
                          parentLayout={parent().layout}
                          panelId={() => panelId}
                          selectedPanel={props.selectedPanel}
                          selectPanel={props.selectPanel}
                          dbgHeader={props.dbgHeader}
                        />
                        <Show when={idx() !== parent().children.length - 1}>
                          <ResizeHandle
                            tree={props.tree}
                            setTree={props.setTree}
                            panelId={() => panelId}
                            parent={parent}
                            idx={idx}
                          />
                        </Show>
                      </>
                    )}
                  </For>
                </div>
              </Match>
            </Switch>
          )}
        </MatchTag>
      </Switch>
    </div>
  );
};

type ResizeHandleProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;
  panelId: () => Panel.ID;

  parent: () => Panel.Node.Parent;
  idx: () => number;
};

const ResizeHandle = (props: ResizeHandleProps) => {
  let resizeRef!: HTMLDivElement;

  onMount(() => {
    assert(resizeRef !== undefined);

    const dragCleanup = draggable({
      element: resizeRef,

      onGenerateDragPreview: ({ nativeSetDragImage }) => {
        disableNativeDragPreview({ nativeSetDragImage });
        preventUnhandled.start();
      },

      getInitialData: () =>
        // false positive
        // eslint-disable-next-line solid/reactivity
        Effect.gen(function* () {
          const parent = props.parent();
          const nodeId = props.panelId();
          const node = yield* Panel.Node.get(props.tree, { id: nodeId });

          const nextNodeId = parent.children[props.idx() + 1];
          // we should never rendered after be the last one
          assert(
            nextNodeId !== undefined,
            "Trying to place a resize handle when there is no next node",
          );
          const nextNode = yield* Panel.Node.get(props.tree, {
            id: nextNodeId,
          });

          const parentRect = resizeRef.parentElement?.getBoundingClientRect();
          assert(parentRect !== undefined);

          const parentLayout = parent.layout;
          const parentSize =
            parentLayout === "vertical" ? parentRect.height : parentRect.width;
          const size = parentSize * node.percentOfParent;
          const nextSize = parentSize * nextNode.percentOfParent;

          return {
            parentLayout,
            parentSize,
            size,
            nextSize,
            nodeId,
            nextNodeId,
          };
        }).pipe(Effect.runSync),

      onDrag: ({ location, source }) =>
        // false positive
        // eslint-disable-next-line solid/reactivity
        Effect.gen(function* () {
          const parentLayout = source.data.parentLayout as Panel.Layout;
          const parentSize = source.data.parentSize as number;
          const size = source.data.size as number;
          const nextSize = source.data.nextSize as number;
          const nodeId = source.data.nodeId as Panel.ID;
          const nextNodeId = source.data.nextNodeId as Panel.ID;

          const delta =
            parentLayout === "vertical"
              ? location.current.input.clientY - location.initial.input.clientY
              : location.current.input.clientX - location.initial.input.clientX;

          const totalAvailableSpace = size + nextSize;
          // const margin = 20;
          const margin = parentSize * 0.05;

          const newSize = Order.clamp(Order.number)({
            minimum: margin,
            maximum: totalAvailableSpace - margin,
          })(size + delta);
          const nextNewSize = Order.clamp(Order.number)({
            minimum: margin,
            maximum: totalAvailableSpace - margin,
          })(nextSize - delta);

          const newPercent = newSize / parentSize;
          const nextNewPercent = nextNewSize / parentSize;

          yield* Panel.Node.update(props.setTree, {
            id: nodeId,
            props: {
              percentOfParent: Panel.Percent(newPercent),
            },
          });
          yield* Panel.Node.update(props.setTree, {
            id: nextNodeId,
            props: {
              percentOfParent: Panel.Percent(nextNewPercent),
            },
          });
        }).pipe(Effect.runSync),

      onDrop: () => {
        preventUnhandled.stop();
      },
    });

    onCleanup(() => {
      dragCleanup();
    });
  });

  return (
    <div
      ref={resizeRef}
      class={cn(
        "relative bg-theme-border transition-colors hover:bg-theme-deemphasis",
        props.parent().layout === "vertical"
          ? "h-[1px] w-full"
          : "w-[1px] h-full",
        css`
          &::before {
            content: "";
            position: absolute;
            ${props.parent().layout === "vertical"
              ? `
              cursor: ns-resize;
              width: 100%;
              height: 7px;
              top: -2px;
              `
              : `
              cursor: ew-resize;
              height: 100%;
              width: 7px;
              left: -2px;
              `}
          }
        `,
      )}
      style={{}}
    />
  );
};

export type TabBarDropData = {
  parent: Panel.ID.Parent;
} & Brand.Brand<"TabBarDropData">;
export const TabBarDropData = Brand.nominal<TabBarDropData>();

// helper because pdnd uses `Record<string, string | unknown>` for generic data
// making it hard to use effects brand api
export const isTabBarDropData = (obj: any): obj is TabBarDropData => {
  return TabBarDropData.is(obj);
};

type TabBarProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  parent: () => Panel.Node.Parent;
};

const TabBar = (props: TabBarProps) => {
  const [hasDroppable, setHasDroppable] = createSignal(false);

  let ref!: HTMLDivElement;
  onMount(() => {
    // setup this element as a place where we can drop elements
    // we provide data for monitorForElements to learn about it from
    // the "destination"
    // has access to "source"s and is able to determine if they can or
    // cannot be dropped here
    // doesn't handle the drop itself
    const cleanup = dropTargetForElements({
      element: ref,

      getData: () =>
        TabBarDropData({
          parent: props.parent().id,
        }) as any,

      canDrop: ({ source }) => {
        if (isTabHandleDragData(source.data)) return true;

        return false;
      },
      onDragEnter: ({ source }) => {
        if (!isTabHandleDragData(source.data)) return;

        setHasDroppable(true);
      },
      onDragLeave: () => setHasDroppable(false),
      onDrop: () => setHasDroppable(false),
    });
    onCleanup(() => cleanup());
  });

  return (
    <div
      ref={ref}
      class={cn(
        "flex items-center px-1 w-full h-6 border-b border-theme-border",
        hasDroppable() && "bg-theme-panel-tab-background-drop-target",
      )}
    >
      <For each={props.parent().children}>
        {(panel) => (
          <TabHandle
            tree={props.tree}
            setTree={props.setTree}
            parent={props.parent}
            panelId={() => panel}
          />
        )}
      </For>
    </div>
  );
};

export type TabHandleDragData = {
  parent: Panel.ID.Parent;
  panel: Panel.ID;
} & Brand.Brand<"TabHandleDragData">;
export const TabHandleDragData = Brand.nominal<TabHandleDragData>();

// helper because pdnd uses `Record<string, string | unknown>` for generic data
// making it hard to use effects brand api
export const isTabHandleDragData = (obj: any): obj is TabHandleDragData => {
  return TabHandleDragData.is(obj);
};

type TabHandleProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  parent: () => Panel.Node.Parent;
  panelId: () => Panel.ID;
};

const TabHandle = (props: TabHandleProps) => {
  const selected = () =>
    Option.getOrElse(
      // false positive
      // eslint-disable-next-line solid/reactivity
      Option.map(props.parent().active, (active) => active === props.panelId()),
      () => false,
    );

  const panel = () =>
    Panel.Node.get(props.tree, { id: props.panelId() }) //
      .pipe(Effect.runSync);

  const [dragging, setDragging] = createSignal<boolean>(false);

  let ref!: HTMLDivElement;
  onMount(() => {
    // setup element to be dragged
    // we provide some data for other listeners to get the info for
    // the "source"
    const cleanup = draggable({
      element: ref,

      getInitialData: () =>
        TabHandleDragData({
          parent: props.parent().id,
          panel: props.panelId(),
        }) as any,

      // called just before the drag,
      // allowing us to change how preview will look
      onGenerateDragPreview: () => setDragging(true),
      onDrop: () => setDragging(false),
    });
    onCleanup(() => cleanup());
  });

  return (
    <div
      ref={ref}
      class={cn(
        "flex items-center h-full px-0.5 first:border-l border-r text-xs leading-none border-theme-border bg-theme-panel-tab-background-idle hover:bg-theme-panel-tab-background-active gap-1 group",
        selected() && "bg-theme-panel-tab-background-active",
        dragging() && "opacity-80 border-transparent",
      )}
      onClick={() =>
        Panel.Node.Parent.update(props.setTree, {
          id: props.parent().id,
          props: {
            active: Option.some(props.panelId()),
          },
        }).pipe(Effect.runSync)
      }
    >
      <div class="size-3.5">{/* icon placeholder*/}</div>

      <MapOption on={Panel.Node.$as("leaf")(panel())} fallback="<parent>">
        {(leaf) => leaf().title}
      </MapOption>

      <Button
        as={Icon}
        kind="close"
        variant="icon"
        size="icon"
        class={cn(
          "size-3.5 opacity-0 group-hover:opacity-100",
          dragging() && "opacity-0",
        )}
      />
    </div>
  );
};
