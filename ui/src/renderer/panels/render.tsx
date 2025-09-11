import {
  createMemo,
  createSignal,
  For,
  onCleanup,
  onMount,
  Show,
  Switch,
} from "solid-js";
import { css } from "solid-styled-components";
import { MapOption } from "solid-effect";

import { Data, Effect, Match, Option, Order } from "effect";

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
        console.log("drop target count: ", location.current.dropTargets.length);

        if (
          isDragDataForTab(source.data) &&
          isDropDataForTab(destination.data)
        ) {
          const dragForTab = source.data;
          const dropForTab = destination.data;

          Panel.Node.reParent(props.setTree, {
            id: dragForTab.panel,
            newParentId: dropForTab.parent,
            idx: dropForTab.idx,
          }).pipe(Effect.runSync);
        }

        // @TODO: drop zones within panels for tree manipulation
      },
    });
    onCleanup(() => cleanup());
  });

  return (
    <RenderPanel
      tree={props.tree}
      setTree={props.setTree}
      splitDirection={() => "vertical"}
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
  splitDirection: () => Panel.Layout.SplitDirection;
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
      style={Match.value(props.splitDirection()).pipe(
        Match.when("vertical", () => ({
          width: "100%",
          height: panel().percentOfParent * 100 + "%",
        })),
        Match.when("horizontal", () => ({
          height: "100%",
          width: panel().percentOfParent * 100 + "%",
        })),
        Match.exhaustive,
      )}
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

      <div class="relative w-full h-full">
        <Switch>
          <MatchTag on={panel()} tag="leaf">
            {(_leaf) => (
              <>
                <div class="w-full h-full">some content</div>
              </>
            )}
          </MatchTag>
          <MatchTag on={panel()} tag="parent">
            {(parent) => (
              <Switch>
                <MatchTag on={parent().layout} tag="tabs">
                  {(layout) => (
                    <TabBar
                      tree={props.tree}
                      setTree={props.setTree}
                      parent={parent}
                      layout={layout}
                    />
                  )}
                </MatchTag>
                <MatchTag on={parent().layout} tag="split">
                  {(split) => (
                    <div
                      class={cn(
                        "flex w-full h-full",
                        Match.value(props.splitDirection()).pipe(
                          Match.when("vertical", () => "flex-row"),
                          Match.when("horizontal", () => "flex-col"),
                          Match.exhaustive,
                        ),
                      )}
                    >
                      <For each={split().children}>
                        {(panelId, idx) => (
                          <>
                            <RenderPanel
                              tree={props.tree}
                              setTree={props.setTree}
                              splitDirection={() => split().direction}
                              panelId={() => panelId}
                              selectedPanel={props.selectedPanel}
                              selectPanel={props.selectPanel}
                              dbgHeader={props.dbgHeader}
                            />
                            <Show when={idx() !== split().children.length - 1}>
                              <ResizeHandle
                                tree={props.tree}
                                setTree={props.setTree}
                                panelId={() => panelId}
                                splitDirection={() => split().direction}
                                parent={parent}
                                idx={idx}
                              />
                            </Show>
                          </>
                        )}
                      </For>
                    </div>
                  )}
                </MatchTag>
              </Switch>
            )}
          </MatchTag>
        </Switch>

        <Show when={false}>
          <Switch>
            <MatchTag on={panel()} tag="parent">
              {(parent) => (
                <Show when={parent().layout._tag !== "tabs"}>
                  <div class="absolute top-0 left-0 w-full h-full z-10 grid grid-cols-[2rem_1fr_4rem_1fr_2rem] grid-rows-[2rem_1fr_4rem_1fr_2rem]">
                    {/* left - add split left */}
                    <div class="w-full h-full col-1 row-3 bg-green-500" />
                    {/* right - add split right */}
                    <div class="w-full h-full col-5 row-3 bg-green-500" />
                    {/* top - add split top */}
                    <div class="w-full h-full col-3 row-1 bg-green-500" />
                    {/* bottom - add split top */}
                    <div class="w-full h-full col-3 row-5 bg-green-500" />
                  </div>
                </Show>
              )}
            </MatchTag>
          </Switch>

          <Show
            when={
              // Read as if parent has no children or layout is tabs or is a leaf
              Option.map(
                Panel.Node.$as("parent")(panel()),
                (parent) =>
                  parent.layout.children.length == 0 ||
                  parent.layout._tag === "tabs",
              ).pipe(Option.getOrElse(() => false)) ||
              Panel.Node.$is("leaf")(panel())
            }
          >
            <div class="absolute top-0 left-0 w-full h-full z-10 grid grid-cols-[2rem_1fr_6rem_1fr_2rem] grid-rows-[2rem_1fr_6rem_1fr_2rem]">
              <div class="w-full h-full col-3 row-3 grid grid-cols-3 grid-rows-3">
                {/* middle - add tab or make tabbed */}
                <div class="w-full h-full col-2 row-2 bg-red-600" />

                {/* left - split panel left */}
                <div class="w-full h-full col-1 row-2 bg-red-300" />
                {/* right - split panel right */}
                <div class="w-full h-full col-3 row-2 bg-red-300" />
                {/* top - split panel top */}
                <div class="w-full h-full col-2 row-1 bg-red-300" />
                {/* bottom - split panel top */}
                <div class="w-full h-full col-2 row-3 bg-red-300" />
              </div>
            </div>
          </Show>
        </Show>
      </div>
    </div>
  );
};

export type DropDataForTab = {
  readonly _tag: "DropDataForTab";
  readonly parent: Panel.ID.Parent;
  readonly idx?: number;
};
export const DropDataForTab = Data.tagged<DropDataForTab>("DropDataForTab");

export const isDropDataForTab = (obj: any): obj is DropDataForTab => {
  return obj._tag === "DropDataForTab";
};

type TabBarProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  parent: () => Panel.Node.Parent;
  layout: () => Panel.Layout.Tabs;
};

const TabBar = (props: TabBarProps) => {
  const [hasDroppable, setHasDroppable] = createSignal(false);

  let dropZoneRef!: HTMLDivElement;
  onMount(() => {
    // setup this element as a place where we can drop elements
    // we provide data for monitorForElements to learn about it from
    // the "destination"
    // has access to "source"s and is able to determine if they can or
    // cannot be dropped here
    // doesn't handle the drop itself
    const cleanup = dropTargetForElements({
      element: dropZoneRef,

      getData: () =>
        DropDataForTab({
          parent: props.parent().id,
        }) as any,

      canDrop: ({ source }) => {
        if (isDragDataForTab(source.data)) return true;

        return false;
      },
      onDragEnter: ({ source }) => {
        if (!isDragDataForTab(source.data)) return;

        setHasDroppable(true);
      },
      onDragLeave: () => setHasDroppable(false),
      onDrop: () => setHasDroppable(false),
    });
    onCleanup(() => cleanup());
  });

  return (
    <div
      // ref={dropZoneRef}
      class={cn(
        "flex items-center px-1 w-full h-6 border-b border-theme-border",
      )}
    >
      <For each={props.layout().children}>
        {(panel, idx) => (
          <TabHandle
            tree={props.tree}
            setTree={props.setTree}
            parent={props.parent}
            panelId={() => panel}
            idx={idx}
          />
        )}
      </For>
      <div
        ref={dropZoneRef}
        class={cn(
          "h-full grow",
          hasDroppable() && "bg-theme-panel-tab-background-drop-target",
        )}
      />
    </div>
  );
};

export type DragDataForTab = {
  readonly _tag: "DragDataForTab";
  readonly parent: Panel.ID.Parent;
  readonly panel: Panel.ID.Leaf;
};
export const DragDataForTab = Data.tagged<DragDataForTab>("DragDataForTab");

export const isDragDataForTab = (obj: any): obj is DragDataForTab => {
  return obj._tag === "DragDataForTab";
};

type TabHandleProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  parent: () => Panel.Node.Parent;
  panelId: () => Panel.ID.Leaf;
  idx: () => number;
};

const TabHandle = (props: TabHandleProps) => {
  const selected = () =>
    Option.getOrElse(
      // false positive
      // eslint-disable-next-line solid/reactivity
      Option.map(props.parent().active, (active) => active === props.panelId()),
      () => false,
    );

  const tab = () =>
    Panel.Node.Leaf.get(props.tree, { id: props.panelId() }) //
      .pipe(Effect.runSync);

  const [dragging, setDragging] = createSignal<boolean>(false);
  const [hasDroppable, setHasDroppable] = createSignal<boolean>(false);

  let ref!: HTMLDivElement;
  onMount(() => {
    // setup element to be dragged
    // we provide some data for other listeners to get the info for
    // the "source"
    const draggableCleanup = draggable({
      element: ref,

      getInitialData: () =>
        DragDataForTab({
          parent: props.parent().id,
          panel: props.panelId(),
        }) as any,

      // called just before the drag,
      // allowing us to change how preview will look
      onGenerateDragPreview: () => setDragging(true),
      onDrop: () => setDragging(false),
    });

    const droppableCleanup = dropTargetForElements({
      element: ref,

      getData: () =>
        DropDataForTab({
          parent: props.parent().id,
          idx: props.idx(),
        }) as any,

      canDrop: ({ source }) => {
        if (isDragDataForTab(source.data)) return true;

        return false;
      },
      onDragEnter: ({ source }) => {
        if (!isDragDataForTab(source.data)) return;

        setHasDroppable(true);
      },
      onDragLeave: () => setHasDroppable(false),
      onDrop: () => setHasDroppable(false),
    });

    onCleanup(() => {
      draggableCleanup();
      droppableCleanup();
    });
  });

  return (
    <div
      ref={ref}
      class={cn(
        "flex items-center h-full px-0.5 first:border-l border-r text-xs leading-none border-theme-border bg-theme-panel-tab-background-idle hover:bg-theme-panel-tab-background-active gap-1 group cursor-pointer",
        selected() && "bg-theme-panel-tab-background-active",
        dragging() &&
          "opacity-60 outline-theme-border -outline-offset-1 outline",
        hasDroppable() && "bg-theme-panel-tab-background-drop-target",
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
      <div class="size-3.5" />

      {tab().title}

      <Button
        as={Icon}
        kind="close"
        variant="icon"
        size="icon"
        noOnClickToOnMouseDown
        class={cn(
          "size-3.5 opacity-0 group-hover:opacity-100",
          dragging() && "opacity-0",
        )}
      />
    </div>
  );
};

type ResizeHandleProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;
  panelId: () => Panel.ID;
  splitDirection: () => Panel.Layout.SplitDirection;

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

          const nextNodeId = parent.layout.children[props.idx() + 1];
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

          const split = Option.getOrThrow(
            Panel.Layout.$as("split")(parent.layout),
          );
          const parentSize =
            split.direction === "vertical"
              ? parentRect.height
              : parentRect.width;
          const size = parentSize * node.percentOfParent;
          const nextSize = parentSize * nextNode.percentOfParent;

          return {
            split,
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
          const split = source.data.split as Panel.Layout.Split;
          const parentSize = source.data.parentSize as number;
          const size = source.data.size as number;
          const nextSize = source.data.nextSize as number;
          const nodeId = source.data.nodeId as Panel.ID;
          const nextNodeId = source.data.nextNodeId as Panel.ID;

          const delta =
            split.direction === "vertical"
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
        props.splitDirection() === "vertical"
          ? "h-[1px] w-full"
          : "w-[1px] h-full",
        css`
          &::before {
            content: "";
            position: absolute;
            ${props.splitDirection() === "vertical"
              ? `
              cursor: ns-resize;
              width: 100%;
              height: 7px;
              top: -3px;
              `
              : `
              cursor: ew-resize;
              height: 100%;
              width: 7px;
              left: -3px;
              `}
          }
        `,
      )}
      style={{}}
    />
  );
};
