import "./clamp";

import { createSignal, For, onMount, Show } from "solid-js";
import { createStore } from "solid-js/store";
import invariant from "tiny-invariant";
import {
  produceUpdate,
  StoreObjectProduce,
  storeObjectProduceFromStore,
} from "./SignalObject";
import Lozenge from "./Lozenge";
import { createEvent, Emitter } from "solid-events";
import { v4 as uuidv4 } from "uuid";
import clsx from "clsx";
import { css } from "solid-styled-components";

import { draggable } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";
import { DragLocationHistory } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";
import { notify } from "./notifications";

import { Brand, Data, Effect, Match, Console, Option } from "effect";

type PanelId = string & Brand.Brand<"PanelId">;
const PanelId = Brand.nominal<PanelId>();

type PanelNodeProps = {
  dbgName: string;
};

type PanelNode = PanelNodeProps & {
  id: PanelId;
  parent?: PanelId;
  children: PanelId[];
};

type PanelTreeData = Record<PanelId, PanelNode>;

type PanelTreeStore = StoreObjectProduce<PanelTreeData>;

class PanelDoesNotExistError extends Data.TaggedError(
  "PanelDoesNotExistError",
)<{}> {
  public readonly parentList: PanelId[] = [];

  constructor(
    public readonly id: PanelId,
    //
  ) {
    super();
  }

  parent = (id: PanelId): PanelDoesNotExistError => {
    this.parentList.push(id);
    return this;
  };
}

class CannotDeleteRootPanelError extends Data.TaggedError(
  "CannotDeleteRootPanelError",
)<{}> {}

const panels = {
  newPanelId: (): PanelId => {
    return PanelId(uuidv4());
  },

  createRootPanelNode: (treeStore: PanelTreeStore): PanelId =>
    panels.newPanelNode(treeStore, { dbgName: "root" }, PanelId("__root")),

  newPanelNode: (
    treeStore: PanelTreeStore,
    props: PanelNodeProps,
    newId?: PanelId,
  ): PanelId =>
    produceUpdate(treeStore, (tree) => {
      const id = newId ?? panels.newPanelId();
      const panel: PanelNode = {
        id: id,
        children: [],
        ...props,
      };
      tree[id] = panel;

      return id;
    }),

  addChild: (
    treeStore: PanelTreeStore,
    parentId: PanelId,
    childId: PanelId,
  ): Effect.Effect<void, PanelDoesNotExistError> =>
    produceUpdate(treeStore, (tree) => {
      const parent = tree[parentId];
      if (!parent) return Effect.fail(new PanelDoesNotExistError(parentId));

      const child = tree[childId];
      if (!child) return Effect.fail(new PanelDoesNotExistError(childId));

      parent.children.push(childId);
      child.parent = parentId;

      return Effect.succeed(void {});
    }),

  deletePanel: (
    treeStore: PanelTreeStore,
    panelId: PanelId,
    removeFromParent: boolean = true,
  ): Effect.Effect<void, CannotDeleteRootPanelError | PanelDoesNotExistError> =>
    produceUpdate(treeStore, (tree) => {
      if (panelId === "__root")
        return Effect.fail(new CannotDeleteRootPanelError());

      const panel = tree[panelId];
      if (!panel) return Effect.fail(new PanelDoesNotExistError(panelId));

      if (removeFromParent && panel.parent) {
        const parent = tree[panel.parent];
        const idx = parent.children.findIndex((id) => id === panelId);
        parent.children.splice(idx, 1);
        panel.parent = undefined;
      }

      return Effect.forEach([...panel.children], (child) =>
        panels.deletePanel(treeStore, child, false),
      ).pipe(
        Effect.mapError((err) =>
          Match.value(err).pipe(
            Match.tag("PanelDoesNotExistError", (err) => err.parent(panelId)),
            Match.orElse((err) => err),
          ),
        ),
        Effect.flatMap(() => {
          delete tree[panelId];

          console.log(`deleted panel: '${panelId}'-'${panel.dbgName}'`);
          return Effect.succeed(void {});
        }),
      );
    }),
};

type EventEmitter = Emitter<Event>;
type Event = Data.TaggedEnum<{
  addChild: {
    id: PanelId;
    childId: PanelId;
  };
  select: {
    id: PanelId | null;
  };
  delete: {
    id: PanelId;
  };
}>;
const Event = Data.taggedEnum<Event>();

type RenderPanelProps = {
  treeStore: PanelTreeStore;
  emitEvent: EventEmitter;
  selectedId: PanelId | null;

  panelId: PanelId;
  indent: number;
};

const RenderPanel = (props: RenderPanelProps) => {
  const panel = props.treeStore.value[props.panelId];

  return (
    <>
      <div class="flex flex-row">
        <div
          style={{
            "padding-left": `${props.indent * 2}rem`,
          }}
        />

        <Lozenge
          class="m-0.5 min-w-10"
          interactive={true}
          highlighted={panel.id === props.selectedId}
          color={panel.children.length === 0 ? "green" : "purple"}
          onClick={(event) => {
            event.stopPropagation();

            props.emitEvent(Event.select({ id: props.panelId }));
          }}
        >
          {panel.dbgName}
        </Lozenge>
      </div>

      <div class="flex flex-col">
        <For each={panel.children}>
          {(panelId) => {
            return (
              <RenderPanel
                {...props}
                panelId={panelId}
                indent={props.indent + 1}
              />
            );
          }}
        </For>
      </div>
    </>
  );
};

type InspectProps = {
  tree: PanelTreeStore;
  panelId: PanelId;
  emitEvent: EventEmitter;
};

const Inspect = (props: InspectProps) => {
  const [newChildName, setNewChildName] = createSignal("");

  const deletePanel = () =>
    props.emitEvent(Event.delete({ id: props.panelId }));

  const dbgName = () => props.tree.value[props.panelId].dbgName;
  const children = () => props.tree.value[props.panelId]?.children;

  const addChild = () => {
    const childName = newChildName().trim();
    if (childName.length === 0) return;

    const childId = panels.newPanelNode(props.tree, { dbgName: childName });
    props.emitEvent(Event.addChild({ id: props.panelId, childId }));
    setNewChildName("");
  };

  return (
    <div class="flex flex-col gap-2">
      <div class="flex flex-row gap-1 items-baseline">
        Selected:
        <Lozenge class="font-mono min-w-10" color="blue">
          {dbgName()}
        </Lozenge>
      </div>
      <div class="flex flex-row gap-2">
        <Lozenge color="red" interactive onClick={deletePanel}>
          delete
        </Lozenge>
        <Lozenge
          color="red"
          interactive
          onClick={() => {
            props.emitEvent(Event.delete({ id: PanelId("does not exist") }));
          }}
        >
          delete fake
        </Lozenge>
      </div>
      Children:
      <div class="flex flex-row pl-6">
        <ul class="flex flex-col gap-1 list-disc">
          <For each={children()}>
            {(childId) => (
              <li>
                <Lozenge
                  class="font-mono min-w-10"
                  color="aqua"
                  interactive
                  onClick={() => {
                    props.emitEvent(Event.select({ id: childId }));
                  }}
                >
                  {props.tree.value[childId].dbgName}
                </Lozenge>
              </li>
            )}
          </For>
        </ul>
      </div>
      <div class="flex flex-row gap-2">
        <input
          type="text"
          value={newChildName()}
          placeholder="new child name"
          name="new child name"
          onInput={({ currentTarget: { value } }) => setNewChildName(value)}
          onKeyDown={({ key }) => {
            if (key === "Enter") addChild();
          }}
        />

        <Lozenge
          color="green"
          class="font-mono w-9 h-9"
          interactive
          onClick={addChild}
        >
          +
        </Lozenge>
      </div>
    </div>
  );
};

type PanelsExplorerProps = {
  treeStore: PanelTreeStore;

  root: PanelId;
  selectedId: PanelId | null;

  emitEvent: EventEmitter;
};

const PanelsExplorer = (props: PanelsExplorerProps) => {
  let sidePanelRef!: HTMLDivElement;
  let dividerRef!: HTMLDivElement;
  const [startingWidth, setStartingWidth] = createSignal(400);

  const getResizeWidth = (location: DragLocationHistory): number => {
    const delta =
      location.current.input.clientX - location.initial.input.clientX;
    const min = window.innerWidth * 0.25;
    const max = window.innerWidth * 0.75;
    return Math.clamp(startingWidth() - delta, min, max);
  };

  onMount(() => {
    invariant(dividerRef);

    return draggable({
      element: dividerRef,

      onGenerateDragPreview: ({ nativeSetDragImage }) => {
        disableNativeDragPreview({ nativeSetDragImage });
        preventUnhandled.start();
      },

      onDrag: ({ location }) => {
        const resizeWidth = getResizeWidth(location);

        sidePanelRef.style.setProperty(
          "--local-resizing-width",
          `${resizeWidth}px`,
        );
      },

      onDrop: ({ location }) => {
        preventUnhandled.stop();

        const resizeWidth = getResizeWidth(location);
        setStartingWidth(resizeWidth);
        sidePanelRef.style.removeProperty("--local-resizing-width");
      },
    });
  });

  return (
    <>
      <div class="flex flex-row w-full h-full">
        <div
          class="font-mono grow h-full p-2"
          // onClick={() => setSelectedId(null)}
          onClick={() => props.emitEvent(Event.select({ id: null }))}
        >
          <RenderPanel
            treeStore={props.treeStore}
            emitEvent={props.emitEvent}
            selectedId={props.selectedId}
            panelId={props.root}
            indent={0}
          />
        </div>

        <div
          ref={dividerRef}
          class={clsx(
            "ml-auto w-[1px] bg-theme-border cursor-ew-resize relative",
            css`
              &::before {
                content: "";
                top: 0;
                position: absolute;
                height: 100%;
                width: 1rem;
                left: -0.5rem;
                cursor: ew-resize;
              }
            `,
          )}
        />

        <div
          ref={sidePanelRef}
          class="flex flex-col p-2 gap-2"
          style={{
            "--local-starting-width": `${startingWidth()}px`,
            width: `var(--local-resizing-width, var(--local-starting-width))`,
          }}
        >
          <Lozenge
            color="pink"
            interactive
            onClick={() => {
              for (const [id, panel] of Object.entries(props.treeStore.value)) {
                console.log("id:", id, ",", "dbgName:", panel.dbgName);
              }
            }}
          >
            Print all panels
          </Lozenge>

          <Show when={props.selectedId !== null}>
            <Inspect
              tree={props.treeStore}
              panelId={props.selectedId!}
              emitEvent={props.emitEvent}
            />
          </Show>
        </div>
      </div>
    </>
  );
};

const Panels2 = () => {
  const treeStore = storeObjectProduceFromStore(createStore<PanelTreeData>());
  const root = panels.createRootPanelNode(treeStore);

  const [selectedId, setSelectedId] = createSignal<PanelId | null>(root);

  const [onEvent, emitEvent] = createEvent<Event>();
  onEvent((event) => {
    Match.value(event).pipe(
      Match.tag("addChild", (event) => {
        panels.addChild(treeStore, event.id, event.childId);
      }),
      Match.tag("select", (event) => {
        // @BUG: ? I don't get it:
        //   without this going between null and PanelId updates the Inspect
        //   but going from PanelId to PanelId doesn't
        //   even this fix just puts it to null first before any change...
        setSelectedId(null);

        setSelectedId((id) => (id === event.id ? null : event.id));
      }),
      Match.tag("delete", (event) =>
        panels.deletePanel(treeStore, event.id).pipe(
          Effect.matchEffect({
            onFailure: (error) =>
              Match.value(error).pipe(
                Match.withReturnType<{
                  notif: string;
                  log: Option.Option<string>;
                }>(),
                Match.tag("CannotDeleteRootPanelError", () => ({
                  notif: "Cannot delete root panel",
                  log: Option.none(),
                })),
                Match.tag("PanelDoesNotExistError", ({ id, parentList }) => ({
                  notif: `Panel width id: '${id}' does not exist`,
                  log: Option.some(
                    `Panel width id: '${id}' does not exist; ` +
                      `parent chain: ${
                        parentList.length !== 0 ? parentList.toString() : "[]"
                      }`,
                  ),
                })),
                Match.exhaustive,
                Effect.succeed,
                Effect.tap(({ notif, log }) =>
                  Console.error(log.pipe(Option.getOrElse(() => notif))),
                ),
                Effect.map(({ notif }) =>
                  Effect.sync(() => notify(notif, { type: "error" })),
                ),
                Effect.runSync,
              ),
            onSuccess: () => {
              if (event.id === selectedId()) setSelectedId(null);
              return Effect.void;
            },
          }),
          Effect.runSync,
        ),
      ),
      Match.exhaustive,
    );
  });

  Effect.gen(function* () {
    const child_a = panels.newPanelNode(treeStore, { dbgName: "a" });
    const child_b = panels.newPanelNode(treeStore, { dbgName: "b" });
    const child_c = panels.newPanelNode(treeStore, { dbgName: "c" });

    yield* panels.addChild(treeStore, root, child_a);
    yield* panels.addChild(treeStore, root, child_b);

    yield* panels.addChild(treeStore, child_a, child_c);
  }).pipe(
    Effect.catchTag("PanelDoesNotExistError", ({ id }) =>
      Console.error(
        `failed to init, got panel does not exist error: id: '${id}'`,
      ),
    ),
    Effect.runSync,
  );

  return (
    <PanelsExplorer
      treeStore={treeStore}
      root={root}
      selectedId={selectedId()}
      emitEvent={emitEvent}
    />
  );
};

export default Panels2;
