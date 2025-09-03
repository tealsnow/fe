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

import Button from "~/ui/components/Button";
import { Icon } from "~/assets/icons";

import * as Panel from "./Panel";
import { storeUpdate } from "~/lib/SignalObject";

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
        // // @FIXME: we might need to check each drop target depending on how
        // //   pdnd handles overlapping valid and invalid drop targets
        // const destination = location.current.dropTargets[0];
        // if (!destination) return;
        // // const sourceIsTabHandleDragData = isTabHandleDragData(source.data);
        // // const destinationIsTabBarDropData = isTabBarDropData(destination.data);
        // if (isTabHandleDragData(source.data)) {
        //   // we have a tab to drop
        //   const tabHandleData = source.data;
        //   if (isTabBarDropData(destination.data)) {
        //     // we are dropping a tab on a tab bar
        //     const tabBarData = destination.data;
        //     // storeUpdate(props.setTree, (tree) =>
        //     //   Effect.gen(function* () {
        //     //     const dragPanel = yield* Panel.getNode(tree, {
        //     //       id: tabHandleData.panel,
        //     //     });
        //     //     const dropPanel = yield* Panel.getNode(tree, {
        //     //       id: tabBarData.panel,
        //     //     });
        //     //     assert(
        //     //       dropPanel.children.length === 0,
        //     //       "cannot drop a panel onto a non leaf panel",
        //     //     );
        //     //     // remove from old panel
        //     //     dragPanel.tabs = dragPanel.tabs.filter(
        //     //       (tab) => tab !== tabHandleData.tab,
        //     //     );
        //     //     // add to new panel
        //     //     dropPanel.tabs.push(tabHandleData.tab);
        //     //   }),
        //     // ).pipe(Effect.runSync);
        //   }
        // }
        // // if (!sourceIsTabHandleDragData || !destinationIsTabBarDropData) return;
        // // if (!isPieceDragData(source.data)) return;
        // // if (!isSquareDragData(destination.data)) return;
        // // const srcData = source.data;
        // // const dstData = destination.data;
        // // const piece = pieces.find((p) =>
        // //   isCoordEqual(p.location, srcData.location),
        // // );
        // // if (
        // //   canMove(srcData.type, srcData.location, dstData.location, pieces) &&
        // //   piece !== undefined
        // // ) {
        // //   const otherPieces = pieces.filter((p) => p !== piece);
        // //   setPieces([
        // //     { type: piece.type, location: dstData.location },
        // //     ...otherPieces,
        // //   ]);
        // // }
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
    Panel.getNode(props.tree, { id: props.panelId() }) //
      .pipe(Effect.runSync),
  );

  const isSelected = () =>
    Option.getOrNull(props.selectedPanel()) === panel().id;

  // if (panel().children.length > 0) assert(panel().tabs.length === 0);
  // if (panel().tabs.length > 0) assert(panel().children.length === 0);
  // const isLeaf = () => panel().tabs.length > 0 || panel().children.length === 0;
  const isLeaf = () => panel().children.length === 0;

  return (
    <div
      class={cn(
        "flex flex-col w-full h-full outline-theme-colors-purple-border/80 -outline-offset-1",
        isSelected() && "outline",
        // "border-theme-colors-purple-border border p-[1px]",
        // selected() && "border-2 p-0",
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
        <div class="flex flex-row w-full h-fit p-0.5 gap-1 items-center border border-theme-colors-orange-border">
          <Button
            color="orange"
            size="small"
            highlighted={isSelected()}
            onClick={() => props.selectPanel(panel().id)}
          >
            {panel().dbgName}
          </Button>
        </div>
      </Show>

      <Switch>
        <Match when={isLeaf()}>
          <div class="w-full h-full">
            <TabBar setTree={props.setTree} panel={panel} />

            {/* content */}
          </div>
        </Match>
        <Match when={!isLeaf()}>
          <div
            class={cn(
              "flex w-full h-full",
              panel().layout === "vertical" ? "flex-col" : "flex-row",
            )}
          >
            <For each={panel().children}>
              {(panelId, idx) => (
                <>
                  <RenderPanel
                    tree={props.tree}
                    setTree={props.setTree}
                    parentLayout={panel().layout}
                    panelId={() => panelId}
                    selectedPanel={props.selectedPanel}
                    selectPanel={props.selectPanel}
                    dbgHeader={props.dbgHeader}
                  />
                  <Show when={idx() !== panel().children.length - 1}>
                    <ResizeHandle
                      tree={props.tree}
                      setTree={props.setTree}
                      panelId={() => panelId}
                      parent={panel}
                      idx={idx}
                    />
                  </Show>
                </>
              )}
            </For>
          </div>
        </Match>
      </Switch>
    </div>
  );
};

type ResizeHandleProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;
  panelId: () => Panel.ID;

  parent: () => Panel.Node;
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
        Effect.gen(function* () {
          const parent = props.parent();
          const nodeId = props.panelId();
          const node = yield* Panel.getNode(props.tree, { id: nodeId });

          const nextNodeId = parent.children[props.idx() + 1];
          // we should never rendered after be the last one
          assert(
            nextNodeId !== undefined,
            "Trying to place a resize handle when there is no next node",
          );
          const nextNode = yield* Panel.getNode(props.tree, { id: nextNodeId });

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

          yield* Panel.updateNode(props.setTree, {
            id: nodeId,
            props: {
              percentOfParent: Panel.Percent(newPercent),
            },
          });
          yield* Panel.updateNode(props.setTree, {
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
  panel: Panel.ID;
} & Brand.Brand<"TabBarDropData">;
export const TabBarDropData = Brand.nominal<TabBarDropData>();

// helper because pdnd uses `Record<string, string | unknown>` for generic data
// making it hard to use effects brand api
export const isTabBarDropData = (obj: any): obj is TabBarDropData => {
  return TabBarDropData.is(obj);
};

type TabBarProps = {
  setTree: Panel.SetTree;
  panel: () => Panel.Node;
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
          panel: props.panel().id,
        }) as any,

      canDrop: ({ source }) => {
        // if (!isTabHandleDragData(source.data)) return false;

        return true;
      },
      onDragEnter: ({ source }) => {
        // if (!isTabHandleDragData(source.data)) return;

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
      {/*<For each={props.panel().tabs}>
        {(tab, idx) => (
          <TabHandle
            setTree={props.setTree}
            panel={props.panel}
            idx={idx}
            tab={() => tab}
          />
        )}
      </For>*/}
    </div>
  );
};

// export type TabHandleDragData = {
//   // tab: Panel.Tab;
//   panel: Panel.ID;
// } & Brand.Brand<"TabHandleDragData">;
// export const TabHandleDragData = Brand.nominal<TabHandleDragData>();

// // helper because pdnd uses `Record<string, string | unknown>` for generic data
// // making it hard to use effects brand api
// export const isTabHandleDragData = (obj: any): obj is TabHandleDragData => {
//   return TabHandleDragData.is(obj);
// };

// type TabHandleProps = {
//   setTree: Panel.SetTree;

//   panel: () => Panel.Node;
//   idx: () => number;
//   tab: () => Panel.Tab;
// };

// const TabHandle = (props: TabHandleProps) => {
//   const selected = () => props.idx() === props.panel().selectedPanel;

//   const [dragging, setDragging] = createSignal<boolean>(false);

//   let ref!: HTMLDivElement;
//   onMount(() => {
//     // setup element to be dragged
//     // we provide some data for other listeners to get the info for
//     // the "source"
//     const cleanup = draggable({
//       element: ref,

//       getInitialData: () =>
//         TabHandleDragData({
//           panel: props.panel().id,
//           tab: props.tab(),
//         }) as any,

//       // called just before the drag,
//       // allowing us to change how preview will look
//       onGenerateDragPreview: () => setDragging(true),
//       onDrop: () => setDragging(false),
//     });
//     onCleanup(() => cleanup());
//   });

//   return (
//     <div
//       ref={ref}
//       class={cn(
//         "flex items-center h-full px-0.5 first:border-l border-r text-xs leading-none border-theme-border bg-theme-panel-tab-background-idle hover:bg-theme-panel-tab-background-active gap-0.5 group",
//         selected() && "bg-theme-panel-tab-background-active",
//         dragging() && "opacity-80 border-transparent",
//       )}
//       onClick={() =>
//         Panel.updateNode(props.setTree, {
//           id: props.panel().id,
//           props: {
//             selectedPanel: props.idx(),
//           },
//         }).pipe(Effect.runSync)
//       }
//     >
//       <div class="size-3.5">{/* icon placeholder*/}</div>

//       {props.tab().title}

//       <Button
//         as={Icon}
//         kind="close"
//         variant="icon"
//         size="icon"
//         class={cn(
//           "size-3.5 opacity-0 group-hover:opacity-100",
//           dragging() && "opacity-0",
//         )}
//       />
//     </div>
//   );
// };
