import {
  Accessor,
  createMemo,
  createSignal,
  For,
  onCleanup,
  onMount,
  ParentProps,
  Setter,
  Show,
  Switch,
} from "solid-js";
import { render as solidRender } from "solid-js/web";
import { css } from "solid-styled-components";
import { MapOption } from "solid-effect";

import { Data, Effect, Match, Option, Order } from "effect";

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

import { cn } from "~/lib/cn";
import assert from "~/lib/assert";
import { MatchTag } from "~/lib/MatchTag";

import Button from "~/ui/components/Button";
import { Icon } from "~/assets/icons";

import * as Panel from "./Panel";
import { Ref } from "solid-js";
import ThemeProvider, { useTheme } from "~/ThemeProvider";
import { CleanupFn } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";

import { effectEdgeRunSync } from "./panels";

export type RenderPanelsProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  selectedPanel: () => Option.Option<Panel.ID>;
  selectPanel: (id: Panel.ID) => void;
  dbgHeader: () => boolean;
};

export const RenderPanels = (props: RenderPanelsProps) => {
  onMount(() => {
    /* eslint-disable solid/reactivity */

    const cleanup = monitorForElements({
      onDrop: ({ source, location }) => {
        // @FIXME: we might need to check each drop target depending on how
        //   pdnd handles overlapping valid and invalid drop targets
        const destination = location.current.dropTargets[0];
        if (!destination) return;
        console.log("drop target count: ", location.current.dropTargets.length);

        Match.value({
          source: source.data,
          destination: destination.data,
        }).pipe(
          Match.when(
            {
              source: (source) => isDragDataForTab(source),
              destination: (destination) => isDropDataForTab(destination),
            },
            ({ source: dragForTab, destination: dropForTab }) =>
              Panel.Node.reParent(props.setTree, {
                id: dragForTab.panel,
                newParentId: dropForTab.parent,
                idx: dropForTab.idx,
              }),
          ),
          Match.when(
            {
              source: (source) => isDragDataForTab(source),
              destination: (destination) =>
                isDropDataForSplitManipCenter(destination),
            },
            ({ source: dragForTab, destination: dropForSplitManipCenter }) => {
              const handleDropMiddle = () =>
                Match.value(dropForSplitManipCenter.panelId).pipe(
                  Match.tag("parent", (parentId) =>
                    // dropping in the middle of an existing parent
                    // we know it already is in a tab layout or otherwise
                    // has no children

                    Panel.Node.reParent(props.setTree, {
                      id: dragForTab.panel,
                      newParentId: parentId,
                    }),
                  ),
                  Match.tag("leaf", (leafId) =>
                    // dropping the tab onto a leaf,
                    // we make a new parent with the leaf as a child
                    // adding the new tab as a child as well

                    Effect.gen(function* () {
                      const newParentId = yield* Panel.Node.promoteToParent(
                        props.setTree,
                        {
                          id: leafId,
                          layout: Panel.Layout.Tabs(),
                        },
                      );

                      yield* Panel.Node.reParent(props.setTree, {
                        id: dragForTab.panel,
                        newParentId,
                      });
                    }),
                  ),
                  Match.exhaustive,
                );

              const handleDir = (
                splitDirection: Panel.Layout.SplitDirection,
                idx: number,
              ) =>
                Effect.gen(function* () {
                  const newParentId = yield* Panel.Node.promoteToParent(
                    props.setTree,
                    {
                      id: dropForSplitManipCenter.panelId,
                      layout: Panel.Layout.Split({ direction: splitDirection }),
                    },
                  );

                  yield* Panel.Node.setPercentOfParent(props.setTree, {
                    id: dragForTab.panel,
                    percent: Panel.Percent(1),
                  });

                  yield* Panel.Node.reParent(props.setTree, {
                    id: dragForTab.panel,
                    newParentId,
                    idx,
                  });
                });

              return Match.value(dropForSplitManipCenter.kind).pipe(
                // we are dropping a tab on the center,
                // adding it to the tab list
                Match.when("center-middle", () => handleDropMiddle()),
                // we are dropping the tab onto the center-{dir}
                // we create a new parent with the panel as a child
                // adding the dropped tab on the correct side
                Match.when("center-left", () => handleDir("horizontal", 0)),
                Match.when("center-right", () => handleDir("horizontal", 1)),
                Match.when("center-top", () => handleDir("vertical", 0)),
                Match.when("center-bottom", () => handleDir("vertical", 1)),
                Match.exhaustive,
              );
            },
          ),
          Match.when(
            {
              source: (source) => isDragDataForTab(source),
              destination: (destination) =>
                isDropDataForSplitManipEdge(destination),
            },
            ({ source: dragForTab, destination: dropForSplitManipEdge }) =>
              Effect.gen(function* () {
                const parent = yield* Panel.Node.Parent.getOrError(props.tree, {
                  parentId: dropForSplitManipEdge.parentId,
                });

                assert(
                  !Panel.Layout.$is("tabs")(parent.layout),
                  "unreachable: shouldn't get a edge manip for tab layout panel",
                );
                const layout = parent.layout;

                const handleEdge = (
                  mainAxis: Panel.Layout.SplitDirection,
                  begin: boolean,
                ) =>
                  Match.value(layout.direction).pipe(
                    // put the dropped panel at the beginning of the children
                    Match.when(mainAxis, () =>
                      Panel.Node.reParent(props.setTree, {
                        id: dragForTab.panel,
                        newParentId: parent.id,
                        idx: begin ? 0 : undefined,
                      }),
                    ),
                    // make a new parent with mainAxis layout with the panel
                    // as the first child
                    Match.when(
                      // Effect cannot understand that this is the opposite of
                      // the mainAxis, and thus gives us an error
                      // The any is to suppress that - it does work as intended
                      Panel.Layout.crossDirection(mainAxis) as any,
                      () =>
                        Effect.gen(function* () {
                          const newParentId = yield* Panel.Node.promoteToParent(
                            props.setTree,
                            {
                              id: parent.id,
                              layout: Panel.Layout.Split({
                                direction: mainAxis,
                              }),
                            },
                          );

                          yield* Panel.Node.reParent(props.setTree, {
                            id: dragForTab.panel,
                            newParentId: newParentId,
                            idx: begin ? 0 : undefined,
                          });
                        }),
                    ),
                    Match.exhaustive,
                  );

                // prettier-ignore
                yield* Match.value(dropForSplitManipEdge.kind).pipe(
                  Match.when("edge-left", () =>
                    handleEdge("horizontal", true),
                  ),
                  Match.when("edge-right", () =>
                    handleEdge("horizontal", false),
                  ),
                  Match.when("edge-top", () =>
                    handleEdge("vertical", true),
                  ),
                  Match.when("edge-bottom", () =>
                    handleEdge("vertical", false),
                  ),
                  Match.exhaustive,
                );
              }),
          ),
          Match.orElse(() => Effect.void),
          effectEdgeRunSync,
        );
      },
    });
    onCleanup(() => cleanup());
    /* eslint-enable solid/reactivity */
  });

  return (
    <RenderPanel
      tree={props.tree}
      setTree={props.setTree}
      parentSplitDirection={() => "horizontal"}
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

  parentSplitDirection: () => Panel.Layout.SplitDirection;
  panelId: () => Panel.ID;
  selectedPanel: () => Option.Option<Panel.ID>;
  selectPanel: (id: Panel.ID) => void;

  dbgHeader: () => boolean;
};

export const RenderPanel = (props: RenderPanelProps) => {
  const panel = createMemo(() =>
    Panel.Node.getOrError(props.tree, { id: props.panelId() }) //
      .pipe(effectEdgeRunSync),
  );

  const isSelected = () =>
    Option.getOrNull(props.selectedPanel()) === panel().id;

  const [panelHover, setPanelHover] = createSignal(false);

  let panelRef!: HTMLDivElement;
  onMount(() => {
    // this is not a real drop target, just something for us to detect a tab
    const cleanup = dropTargetForElements({
      element: panelRef,

      onDragStart: ({ source }) => {
        if (!isDragDataForTab(source.data)) return;
        setPanelHover(true);
      },
      onDragEnter: ({ source }) => {
        if (!isDragDataForTab(source.data)) return;
        setPanelHover(true);
      },
      onDragLeave: () => setPanelHover(false),
      onDrop: () => setPanelHover(false),
    });
    onCleanup(() => cleanup());
  });

  return (
    <div
      ref={panelRef}
      class={cn(
        "flex flex-col w-full h-full outline-theme-colors-purple-border/80 -outline-offset-1",
        isSelected() && "outline",
      )}
      style={Match.value(props.parentSplitDirection()).pipe(
        Match.when("vertical", () => ({
          width: "100%",
          height: `${panel().percentOfParent * 100}%`,
        })),
        Match.when("horizontal", () => ({
          height: "100%",
          width: `${panel().percentOfParent * 100}%`,
        })),
        Match.exhaustive,
      )}
      data-panel-id={props.panelId().uuid}
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
            {(leaf) => <RenderPanelLeaf leaf={leaf} />}
          </MatchTag>
          <MatchTag on={panel()} tag="parent">
            {(parent) => (
              <RenderPanelParent
                tree={props.tree}
                setTree={props.setTree}
                parent={parent}
                selectedPanel={props.selectedPanel}
                selectPanel={props.selectPanel}
                dbgHeader={props.dbgHeader}
              />
            )}
          </MatchTag>
        </Switch>

        <Show when={panelHover()}>
          <PanelDropOverlay panel={panel} />
        </Show>
      </div>
    </div>
  );
};

type PanelTitleProps = ParentProps<{
  ref?: Ref<HTMLDivElement>;
  class?: string;
}>;

const PanelTitle = (props: PanelTitleProps) => {
  return (
    <div
      ref={props.ref}
      class={cn(
        "flex items-center min-h-6 border-b border-theme-border",
        props.class,
      )}
    >
      {props.children}
    </div>
  );
};

type RenderPanelLeafProps = {
  leaf: () => Panel.Node.Leaf;
};

const RenderPanelLeaf = (props: RenderPanelLeafProps) => {
  const theme = useTheme();

  let ref!: HTMLDivElement;
  onMount(() => {
    const cleanup = draggable({
      element: ref,

      getInitialData: () =>
        DragDataForTab({
          parent: props.leaf().parent.pipe(Option.getOrThrow),
          panel: props.leaf().id,
        }) as any,

      onGenerateDragPreview: ({ nativeSetDragImage }) => {
        setCustomNativeDragPreview({
          getOffset: pointerOutsideOfPreview({
            x: "calc(var(--spacing) * 2)",
            y: "calc(var(--spacing) * 2)",
          }),
          render: ({ container }) => {
            solidRender(() => {
              return (
                <ThemeProvider theme={theme.theme()}>
                  <PanelTitle class="px-1 min-w-12 border border-theme-border">
                    {props.leaf().title}
                  </PanelTitle>
                </ThemeProvider>
              );
            }, container);
          },
          nativeSetDragImage,
        });
      },
    });
    onCleanup(() => cleanup());
  });

  return (
    <div class="w-full h-full">
      <PanelTitle ref={ref} class="pl-2 border-b">
        {props.leaf().title}
      </PanelTitle>
      <div class="flex w-full h-full items-center justify-center">
        some content
      </div>
    </div>
  );
};

type RenderPanelParentProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  parent: () => Panel.Node.Parent;

  selectedPanel: () => Option.Option<Panel.ID>;
  selectPanel: (id: Panel.ID) => void;

  dbgHeader: () => boolean;
};

const RenderPanelParent = (props: RenderPanelParentProps) => {
  return (
    <Switch>
      <MatchTag on={props.parent().layout} tag="tabs">
        {(tabs) => (
          <div class="w-full h-full flex flex-col">
            <TabBar
              tree={props.tree}
              setTree={props.setTree}
              parent={props.parent}
              tabs={tabs}
            />

            <MapOption
              on={tabs().active}
              fallback={
                <div class="w-full h-full flex items-center justify-center">
                  no tab selected
                </div>
              }
            >
              {(activeId) => {
                const active = () =>
                  Panel.Node.Leaf.getOrError(props.tree, { id: activeId() }) //
                    .pipe(effectEdgeRunSync);

                return (
                  <MapOption
                    on={active().content}
                    fallback={
                      <div class="w-full h-full flex items-center justify-center">
                        no content
                      </div>
                    }
                  >
                    {(content) => (
                      <div class="w-full h-full">{content()()}</div>
                    )}
                  </MapOption>
                );
              }}
            </MapOption>
          </div>
        )}
      </MatchTag>
      <MatchTag on={props.parent().layout} tag="split">
        {(split) => {
          return (
            <div
              class={cn(
                "flex w-full h-full",
                Match.value(split().direction).pipe(
                  Match.when("vertical", () => "flex-col"),
                  Match.when("horizontal", () => "flex-row"),
                  Match.exhaustive,
                ),
              )}
            >
              <Show
                when={split().children.length > 0}
                fallback={
                  <div class="flex w-full h-full items-center justify-center">
                    No children
                  </div>
                }
              >
                <For each={split().children}>
                  {(panelId, idx) => (
                    <>
                      <RenderPanel
                        tree={props.tree}
                        setTree={props.setTree}
                        parentSplitDirection={() => split().direction}
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
                          parent={props.parent}
                          idx={idx}
                        />
                      </Show>
                    </>
                  )}
                </For>
              </Show>
            </div>
          );
        }}
      </MatchTag>
    </Switch>
  );
};

type PanelDropOverlayProps = {
  panel: () => Panel.Node;
};

type OverlayHandles = {
  [k in SplitManipKind]: {
    ref: HTMLDivElement | undefined;
    hasDrop: Accessor<boolean>;
    setHasDrop: Setter<boolean>;
  };
};

const PanelDropOverlay = (props: PanelDropOverlayProps) => {
  const handles: OverlayHandles = SplitManipKind.reduce((acc, kind) => {
    const [hasDrop, setHasDrop] = createSignal(false);
    acc[kind] = {
      ref: undefined,
      hasDrop,
      setHasDrop,
    };
    return acc;
  }, {} as OverlayHandles);

  onMount(() => {
    const cleanups: CleanupFn[] = [];

    for (const kind of SplitManipKind) {
      const handle = handles[kind];
      if (handle.ref) {
        const cleanup = dropTargetForElements({
          element: handle.ref,

          getData: () => {
            if (isSplitManipKindCenter(kind)) {
              return DropDataForSplitManipCenter({
                panelId: props.panel().id,
                kind,
              }) as any;
            } else {
              const panelId = props.panel().id;
              assert(
                isSplitManipKindEdge(kind),
                "unreachable: if it is not a center kind it must be an edge kind",
              );
              assert(
                Panel.ID.$is("parent")(panelId),
                "unreachable: panel must be a parent for edge split manip",
              );

              return DropDataForSplitManipEdge({
                parentId: panelId,
                kind,
              }) as any;
            }
          },

          canDrop: ({ source }) => {
            if (isDragDataForTab(source.data)) return true;
            return false;
          },
          onDragEnter: () => handle.setHasDrop(true),
          onDragLeave: () => handle.setHasDrop(false),
          onDrop: () => handle.setHasDrop(false),
        });
        cleanups.push(cleanup);
      }
    }

    onCleanup(() => {
      for (const cleanup of cleanups) {
        cleanup();
      }
    });
  });

  return (
    <>
      <Show
        when={Option.flatMap(
          Panel.Node.$as("parent")(props.panel()),
          (parent) => Panel.Layout.$as("split")(parent.layout),
        ).pipe(Option.getOrElse(() => false))}
      >
        <div
          class={cn(
            "absolute top-0 left-0 w-full h-full z-10",
            "grid grid-cols-[2rem_1fr_4rem_1fr_2rem] grid-rows-[2rem_1fr_4rem_1fr_2rem]",
            "pointer-events-none",
          )}
        >
          <For each={SplitManipKindEdge}>
            {(kind) => (
              <div
                ref={handles[kind].ref}
                class={cn(
                  "w-full h-full col-1 row-3 bg-green-500 pointer-events-auto",
                  handles[kind].hasDrop() && "opacity-10",
                  Match.value(kind).pipe(
                    Match.when("edge-left", () => "col-1 row-3"),
                    Match.when("edge-right", () => "col-5 row-3"),
                    Match.when("edge-top", () => "col-3 row-1"),
                    Match.when("edge-bottom", () => "col-3 row-5"),
                    Match.exhaustive,
                  ),
                )}
              />
            )}
          </For>
        </div>
      </Show>

      <Show
        when={
          // Read as if parent has no children or layout is tabs or is a leaf
          Option.map(
            Panel.Node.$as("parent")(props.panel()),
            (parent) =>
              parent.layout.children.length == 0 ||
              parent.layout._tag === "tabs",
          ).pipe(Option.getOrElse(() => false)) ||
          Panel.Node.$is("leaf")(props.panel())
        }
      >
        <div
          class={cn(
            "absolute top-0 left-0 w-full h-full z-10",
            "grid grid-cols-[2rem_1fr_6rem_1fr_2rem] grid-rows-[2rem_1fr_6rem_1fr_2rem]",
            "pointer-events-none",
          )}
        >
          <div class="w-full h-full col-3 row-3 grid grid-cols-3 grid-rows-3">
            <For each={SplitManipKindCenter}>
              {(kind) => (
                <div
                  ref={handles[kind].ref}
                  class={cn(
                    "w-full h-full bg-red-300 pointer-events-auto",
                    handles[kind].hasDrop() && "opacity-10",
                    kind === "center-middle" && "bg-red-600",
                    Match.value(kind).pipe(
                      Match.when("center-middle", () => "col-2 row-2"),
                      Match.when("center-left", () => "col-1 row-2"),
                      Match.when("center-right", () => "col-3 row-2"),
                      Match.when("center-top", () => "col-2 row-1"),
                      Match.when("center-bottom", () => "col-2 row-3"),
                      Match.exhaustive,
                    ),
                  )}
                />
              )}
            </For>
          </div>
        </div>
      </Show>
    </>
  );
};

type TabBarProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  parent: () => Panel.Node.Parent;
  tabs: () => Panel.Layout.Tabs;
};

const TabBar = (props: TabBarProps) => {
  const [hasDroppable, setHasDroppable] = createSignal(false);

  let dropZoneRef!: HTMLDivElement;
  onMount(() => {
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
      onDragEnter: () => setHasDroppable(true),
      onDragLeave: () => setHasDroppable(false),
      onDrop: () => setHasDroppable(false),
    });
    onCleanup(() => cleanup());
  });

  return (
    <PanelTitle class="px-1">
      <For each={props.tabs().children}>
        {(panel, idx) => (
          <TabHandle
            tree={props.tree}
            setTree={props.setTree}
            parent={props.parent}
            tabs={props.tabs}
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
    </PanelTitle>
  );
};

type TabHandleProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  parent: () => Panel.Node.Parent;
  tabs: () => Panel.Layout.Tabs;
  panelId: () => Panel.ID.Leaf;
  idx: () => number;
};

const TabHandle = (props: TabHandleProps) => {
  const selected = () =>
    Option.getOrElse(
      // false positive
      // eslint-disable-next-line solid/reactivity
      Option.map(props.tabs().active, (active) => active === props.panelId()),
      () => false,
    );

  const tab = () =>
    Panel.Node.Leaf.get(props.tree, { id: props.panelId() }) //
      .pipe(effectEdgeRunSync);

  const [dragging, setDragging] = createSignal<boolean>(false);
  const [hasDroppable, setHasDroppable] = createSignal<boolean>(false);

  let ref!: HTMLDivElement;
  onMount(() => {
    const cleanup = pdndCombine(
      draggable({
        element: ref,

        getInitialData: () =>
          DragDataForTab({
            parent: props.parent().id,
            panel: props.panelId(),
          }) as any,

        onGenerateDragPreview: () => setDragging(true),
        onDrop: () => setDragging(false),
      }),
      dropTargetForElements({
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
        onDragEnter: () => setHasDroppable(true),
        onDragLeave: () => setHasDroppable(false),
        onDrop: () => setHasDroppable(false),
      }),
    );

    onCleanup(() => cleanup());
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
            layout: {
              ...props.tabs(),
              active: Option.some(props.panelId()),
            },
          },
        }).pipe(effectEdgeRunSync)
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
        }).pipe(effectEdgeRunSync),

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
        }).pipe(effectEdgeRunSync),

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
    />
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

export type DropDataForTab = {
  readonly _tag: "DropDataForTab";
  readonly parent: Panel.ID.Parent;
  readonly idx?: number;
};
export const DropDataForTab = Data.tagged<DropDataForTab>("DropDataForTab");

export const isDropDataForTab = (obj: any): obj is DropDataForTab => {
  return obj._tag === "DropDataForTab";
};

const SplitManipKindCenter = [
  "center-middle",
  "center-left",
  "center-right",
  "center-top",
  "center-bottom",
] as const;
const isSplitManipKindCenter = (kind: string): kind is SplitManipKindCenter => {
  return SplitManipKindCenter.includes(kind as any);
};
type SplitManipKindCenter = (typeof SplitManipKindCenter)[number];

const SplitManipKindEdge = [
  "edge-left",
  "edge-right",
  "edge-top",
  "edge-bottom",
] as const;
const isSplitManipKindEdge = (kind: string): kind is SplitManipKindEdge => {
  return SplitManipKindEdge.includes(kind as any);
};
type SplitManipKindEdge = (typeof SplitManipKindEdge)[number];

const SplitManipKind = [
  ...SplitManipKindCenter,
  ...SplitManipKindEdge,
] as const;
type SplitManipKind = SplitManipKindCenter | SplitManipKindEdge;

type DropDataForSplitManipCenter = {
  readonly _tag: "DropDataForSplitManipCenter";
  readonly panelId: Panel.ID;
  readonly kind: SplitManipKindCenter;
};
const DropDataForSplitManipCenter = Data.tagged<DropDataForSplitManipCenter>(
  "DropDataForSplitManipCenter",
);
const isDropDataForSplitManipCenter = (
  obj: any,
): obj is DropDataForSplitManipCenter => {
  return obj._tag === "DropDataForSplitManipCenter";
};

type DropDataForSplitManipEdge = {
  readonly _tag: "DropDataForSplitManipEdge";
  readonly parentId: Panel.ID.Parent;
  readonly kind: SplitManipKindEdge;
};
const DropDataForSplitManipEdge = Data.tagged<DropDataForSplitManipEdge>(
  "DropDataForSplitManipEdge",
);
const isDropDataForSplitManipEdge = (
  obj: any,
): obj is DropDataForSplitManipEdge => {
  return obj._tag === "DropDataForSplitManipEdge";
};
