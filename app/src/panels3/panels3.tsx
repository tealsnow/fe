import { createStore } from "solid-js/store";
import {
  createMemo,
  createSignal,
  For,
  onCleanup,
  onMount,
  Show,
} from "solid-js";
import { css } from "solid-styled-components";
import { makePersisted } from "@solid-primitives/storage";

import { Effect, Option, Order } from "effect";

import { draggable } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";

import { cn } from "~/lib/cn";
import assert from "~/lib/assert";
import Lozenge from "~/Lozenge";

import * as Panel from "./Panel";
import Inspector from "./Inspector";

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

  const selected = () => Option.getOrNull(props.selectedPanel()) === panel().id;

  return (
    <div
      class={cn(
        "flex flex-col w-full h-full border-theme-colors-purple-border",
        selected() && "border",
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
        <div class="flex flex-row w-full h-fit p-0.5 gap-1 items-center border-b border-theme-colors-purple-border">
          <Lozenge
            color="orange"
            class="min-w-10"
            interactive
            highlighted={selected()}
            onClick={() => props.selectPanel(panel().id)}
          >
            {panel().dbgName}
          </Lozenge>
          {(panel().percentOfParent * 100).toFixed(2)}% Children %:
          {Panel.validateChildrenSizes(props.tree, {
            id: panel().id,
          }).pipe(
            Effect.map(({ ok, difference }) => (
              <>
                {ok ? (
                  <div class="text-green-500">OK</div>
                ) : (
                  <div class="text-red-500">
                    Error: difference: {difference}
                  </div>
                )}
              </>
            )),
            Effect.runSync,
          )}
        </div>
      </Show>

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

    console.log("added drag handler");

    onCleanup(() => {
      dragCleanup();
    });
  });

  return (
    <div
      ref={resizeRef}
      class={cn(
        "relative bg-theme-border",
        props.parent().layout === "vertical"
          ? "h-[2px] w-full"
          : "w-[2px] h-full",
        css`
          &::before {
            content: "";
            position: absolute;
            ${props.parent().layout === "vertical"
              ? `
              cursor: ns-resize;
              width: 100%;
              height: 8px;
              top: -2px;
              `
              : `
              cursor: ew-resize;
              height: 100%;
              width: 8px;
              left: -2px;
              `}
          }
        `,
      )}
      style={{}}
    />
  );
};

export type RenderPanelsProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;
  selectedPanel: () => Option.Option<Panel.ID>;
  selectPanel: (id: Panel.ID) => void;
  dbgHeader: () => boolean;
};

export const RenderPanels = (props: RenderPanelsProps) => {
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

export const Panels3 = () => {
  const [tree, setTree] = createStore<Panel.Tree>(
    Panel.createTree.pipe(Effect.runSync),
  );

  const [selectedId, setSelectedId] = createSignal<Option.Option<Panel.ID>>(
    Option.some(tree.root),
  );

  const [showExplorer, setShowExplorer] = makePersisted(createSignal(true), {
    name: "show-panel-explorer",
    storage: sessionStorage,
  });

  const [showDbgHeader, setShowDbgHeader] = makePersisted(createSignal(true), {
    name: "show-panel-debug-header",
    storage: sessionStorage,
  });

  onMount(() => {
    Effect.gen(function* () {
      const root = tree.root;

      const a = yield* Panel.createNode(setTree, {
        dbgName: "a",
        layout: "vertical",
      });
      const b = yield* Panel.createNode(setTree, { dbgName: "b" });
      const c = yield* Panel.createNode(setTree, { dbgName: "c" });
      const d = yield* Panel.createNode(setTree, { dbgName: "d" });
      const e = yield* Panel.createNode(setTree, { dbgName: "e" });

      yield* Panel.addChild(setTree, { parentId: root, newChildId: a });
      yield* Panel.addChild(setTree, { parentId: root, newChildId: e });

      yield* Panel.addChild(setTree, { parentId: a, newChildId: b });
      yield* Panel.addChild(setTree, { parentId: a, newChildId: c });
      yield* Panel.addChild(setTree, { parentId: a, newChildId: d });
    }).pipe(Effect.runSync);
  });

  return (
    <div class="flex flex-col w-full h-full">
      <div class="flex flex-row h-8 border-b border-theme-border items-center p-2">
        <div class="ml-auto flex flex-row-reverse gap-2">
          <For
            each={[
              {
                get: showExplorer,
                set: setShowExplorer,
                lbl: "show explorer",
              },
              {
                get: showDbgHeader,
                set: setShowDbgHeader,
                lbl: "show debug header",
              },
            ]}
          >
            {({ get, set, lbl }) => (
              <label class="flex flex-row gap-1">
                <input
                  type="checkbox"
                  checked={get()}
                  id={lbl}
                  class="form-checkbox border-1 border-theme-colors-purple-border
                  bg-theme-colors-purple-background outline-0
                  checked:bg-theme-colors-purple-base ring-offset-0 ring-0"
                  onChange={({ target: { checked } }) => set(checked)}
                />
                {lbl}
              </label>
            )}
          </For>
        </div>
      </div>

      <div class="flex h-full w-full">
        <div
          class={cn(
            "h-full border-r border-theme-border",
            showExplorer() ? "w-[60%]" : "w-full",
          )}
        >
          <RenderPanels
            tree={tree}
            setTree={setTree}
            selectedPanel={selectedId}
            selectPanel={(id) => setSelectedId(Option.some(id))}
            dbgHeader={showDbgHeader}
          />
        </div>

        <Show when={showExplorer()}>
          <div class="w-[40%]">
            <Inspector
              tree={tree}
              setTree={setTree}
              selectedId={selectedId}
              setSelectedId={setSelectedId}
            />
          </div>
        </Show>
      </div>
    </div>
  );
};

export default Panels3;
