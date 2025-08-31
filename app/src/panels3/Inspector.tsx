import { Effect, Option, Order, pipe } from "effect";
import {
  createMemo,
  createSignal,
  For,
  onCleanup,
  onMount,
  Show,
} from "solid-js";
import { css } from "solid-styled-components";
import { MapOption } from "solid-effect";

import { DragLocationHistory } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";
import { draggable } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";

import { cn } from "~/lib/cn";
import Lozenge from "~/Lozenge";

import * as Panel from "./Panel";
import * as Property from "./Property";
import { makePersisted } from "@solid-primitives/storage";

const getPanel = (tree: Panel.Tree, id: Panel.ID) =>
  Panel.getNode(tree, { id }).pipe(Effect.runSync);

export type RenderPanelPillProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  selectedId: () => Option.Option<Panel.ID>;
  selectPanel: (id: Panel.ID) => void;

  panelId: () => Panel.ID;
  indent: number;
};

export const RenderPanelPill = (props: RenderPanelPillProps) => {
  const panel = createMemo(() => getPanel(props.tree, props.panelId()));

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
          highlighted={Option.getOrNull(props.selectedId()) === props.panelId()}
          color={panel().children.length === 0 ? "green" : "purple"}
          onClick={(event) => {
            event.stopPropagation();
            props.selectPanel(props.panelId());
          }}
        >
          {panel().dbgName}
        </Lozenge>
      </div>

      <div class="flex flex-col">
        <For each={panel().children}>
          {(childId) => {
            return (
              <RenderPanelPill
                {...props}
                panelId={() => childId}
                indent={props.indent + 1}
              />
            );
          }}
        </For>
      </div>
    </>
  );
};

type PanelInspectorProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  panelId: () => Panel.ID;
  selectPanel: (id: Panel.ID) => void;
  deselectPanel: () => void;
};

const PanelInspector = (props: PanelInspectorProps) => {
  const panel = createMemo(() => getPanel(props.tree, props.panelId()));

  let newChildInputRef!: HTMLInputElement;
  const [newChildName, setNewChildName] = createSignal<string | null>(null);
  const addChild = () => {
    const name = newChildName();
    if (!name) return;

    Effect.gen(function* () {
      const newChildId = yield* Panel.createNode(props.setTree, {
        dbgName: name,
      });
      yield* Panel.addChild(props.setTree, {
        parentId: panel().id,
        newChildId,
      });
    }).pipe(Effect.runSync);

    setNewChildName(null);
  };

  return (
    <div class="font-mono">
      <Property.PropertyEditor name="panel-inspector" showHeader={true}>
        <Property.StringProperty
          key="Debug name"
          value={panel().dbgName}
          onUpdate={(dbgName) => {
            Panel.updateNode(props.setTree, {
              id: panel().id,
              props: { dbgName },
            }).pipe(Effect.runSync);
          }}
        />

        <Property.ButtonProperty
          key="Delete panel?"
          onClick={Option.getOrUndefined(
            Option.map(
              panel().parent,
              (parentId) => () =>
                Effect.runSync(
                  Effect.gen(function* () {
                    const id = panel().id;
                    props.deselectPanel();
                    yield* Panel.deleteNode(props.setTree, { id });
                    props.selectPanel(parentId);
                  }),
                ),
            ),
          )}
        >
          Delete
        </Property.ButtonProperty>

        <Property.ButtonProperty
          key="Parent"
          onClick={Option.map(
            panel().parent,
            (id) => () => props.selectPanel(id),
          ).pipe(Option.getOrUndefined)}
        >
          {Option.map(panel().parent, (id) =>
            Panel.getNode(props.tree, { id }).pipe(
              Effect.map((panel) => panel.dbgName),
              Effect.runSync,
            ),
          ).pipe(Option.getOrElse(() => "null"))}
        </Property.ButtonProperty>

        <Property.EnumProperty
          key="Layout"
          value={panel().layout}
          options={["vertical", "horizontal"]}
          onChange={(value) => {
            Panel.updateNode(props.setTree, {
              id: panel().id,
              props: {
                layout: value as Panel.Layout,
              },
            }).pipe(Effect.runSync);
          }}
        />

        <Property.ArrayProperty
          key="Children"
          items={Array.from(panel().children).map((id) =>
            Panel.getNode(props.tree, { id }).pipe(
              Effect.map((panel) => panel),
              Effect.runSync,
            ),
          )}
          // preview={(item) => `'${item.dbgName}'`}
          render={(item) => (
            <Lozenge
              class="font-mono min-w-8 h-full p-0 px-1 border-1"
              color="aqua"
              interactive
              onClick={() => props.selectPanel(item.id)}
            >
              {item.dbgName}
            </Lozenge>
          )}
          last={() => (
            <div class="flex h-full gap-1">
              <Show when={newChildName() !== null}>
                <input
                  ref={newChildInputRef}
                  type="text"
                  class={cn(
                    "ring-0 min-h-0 h-full p-0 px-1 pt-0.5 box-border bg-theme-colors-purple-background border border-theme-colors-purple-border",
                  )}
                  size={12}
                  placeholder="new child name"
                  value={newChildName()!}
                  onBlur={() => setTimeout(() => setNewChildName(null), 100)}
                  onInput={({ currentTarget: { value } }) =>
                    setNewChildName(value)
                  }
                  onKeyDown={({ key }) => {
                    switch (key) {
                      case "Enter":
                        addChild();
                        break;
                      case "Escape":
                        setNewChildName(null);
                        break;
                    }
                  }}
                />
              </Show>
              <Lozenge
                class="font-mono min-w-8 h-full p-0 px-1 border-1"
                color="green"
                interactive
                onClick={() => {
                  if (newChildName() !== null) {
                    addChild();
                  } else {
                    setNewChildName("new child");
                    newChildInputRef.focus();
                    newChildInputRef.select();
                  }
                }}
              >
                +
              </Lozenge>
            </div>
          )}
        />

        <Property.ButtonProperty
          key="redistribute children?"
          onClick={() =>
            Panel.redistributeChildren(props.setTree, { id: panel().id }).pipe(
              Effect.runSync,
            )
          }
        >
          redistribute
        </Property.ButtonProperty>

        <Property.ButtonProperty
          key="balance children?"
          onClick={() =>
            Panel.uniformChildren(props.setTree, { id: panel().id }).pipe(
              Effect.runSync,
            )
          }
        >
          balance
        </Property.ButtonProperty>

        <Property.StringProperty
          key="% of parent"
          value={(panel().percentOfParent * 100).toFixed(2)}
          // format={(str) => str + "%"}
          onUpdate={(update) => {
            const num = Order.clamp(Order.number)({
              minimum: 0,
              maximum: 100,
            })(parseFloat(update));

            Effect.gen(function* () {
              yield* Panel.updateNode(props.setTree, {
                id: panel().id,
                props: {
                  percentOfParent: Panel.Percent(num / 100),
                },
              });

              const parent = yield* panel().parent;
              yield* Panel.redistributeChildren(props.setTree, {
                id: parent,
                exclude: [panel().id],
              });
            }).pipe(Effect.runSync);
          }}
        />

        <Property.StringProperty
          key="Children % valid"
          value={pipe(
            Effect.if(panel().children.length !== 0, {
              onFalse: () => Effect.succeed("No children"),
              onTrue: () =>
                Panel.validateChildrenSizes(props.tree, {
                  id: panel().id,
                }).pipe(
                  Effect.flatMap(({ ok, difference }) =>
                    Effect.if(ok, {
                      onTrue: () => Effect.succeed("Valid"),
                      onFalse: () =>
                        Effect.succeed(
                          `Invalid (${(difference * 100).toFixed(2)}%)`,
                        ),
                    }),
                  ),
                ),
            }),
            Effect.runSync,
          )}
        />
      </Property.PropertyEditor>
    </div>
  );
};

export type InspectorProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  selectedId: () => Option.Option<Panel.ID>;
  setSelectedId: (id: Option.Option<Panel.ID>) => void;
};

const Inspector = (props: InspectorProps) => {
  let componentRef!: HTMLDivElement;
  let sidePanelRef!: HTMLDivElement;
  let dividerRef!: HTMLDivElement;

  const [startingSize, setStartingSize] = makePersisted(createSignal(400), {
    storage: sessionStorage,
    name: "panel-inspector-size",
  });

  onMount(() => {
    const getResizeSize = (location: DragLocationHistory): number => {
      const delta =
        location.current.input.clientY - location.initial.input.clientY;

      const margin = componentRef.clientHeight * 0.1;
      return Order.clamp(Order.number)({
        minimum: margin,
        maximum: componentRef.clientHeight - margin,
      })(startingSize() - delta);
    };

    const dragCleanup = draggable({
      element: dividerRef,

      onGenerateDragPreview: ({ nativeSetDragImage }) => {
        disableNativeDragPreview({ nativeSetDragImage });
        preventUnhandled.start();
      },

      onDrag: ({ location }) => {
        const resizeSize = getResizeSize(location);

        sidePanelRef.style.setProperty(
          "--local-resizing-size",
          `${resizeSize}`,
        );
      },

      onDrop: ({ location }) => {
        preventUnhandled.stop();

        const resizeSize = getResizeSize(location);
        setStartingSize(resizeSize);
        sidePanelRef.style.removeProperty("--local-resizing-size");
      },
    });

    onCleanup(() => {
      dragCleanup();
    });
  });

  return (
    <div ref={componentRef} class="flex flex-col w-auto h-full">
      <div
        class="p-2 font-mono grow overflow-auto min-h-0"
        onClick={() => props.setSelectedId(Option.none())}
      >
        <RenderPanelPill
          tree={props.tree}
          setTree={props.setTree}
          selectedId={props.selectedId}
          selectPanel={(id) => props.setSelectedId(Option.some(id))}
          panelId={() => props.tree.root}
          indent={0}
        />
      </div>

      <div
        ref={dividerRef}
        class={cn(
          "h-[1px] bg-theme-border cursor-ns-resize relative",
          css`
            &::before {
              content: "";
              top: 0;
              position: absolute;
              width: 100%;
              height: 1rem;
              left: -0.5rem;
            }
          `,
        )}
      />

      <div
        ref={sidePanelRef}
        class="flex flex-col p-0.5 gap-2 overflow-auto"
        style={{
          "--local-starting-size": startingSize(),
          height: `calc(var(--local-resizing-size, var(--local-starting-size)) * 1px)`,
        }}
      >
        <Lozenge
          class="ml-2 mt-2"
          color="pink"
          interactive
          onClick={() => {
            for (const [id, panel] of Object.entries(props.tree.nodes)) {
              console.log("id:", id, ",", "dbgName:", panel.dbgName);
            }
          }}
        >
          Print all panels
        </Lozenge>

        <MapOption on={props.selectedId()}>
          {(selectedId) => (
            <PanelInspector
              tree={props.tree}
              setTree={props.setTree}
              panelId={selectedId}
              selectPanel={(id) => props.setSelectedId(Option.some(id))}
              deselectPanel={() => props.setSelectedId(Option.none())}
            />
          )}
        </MapOption>
      </div>
    </div>
  );
};

export default Inspector;
