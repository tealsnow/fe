import { Effect, Option, Order, pipe } from "effect";
import { createSignal, For, onCleanup, onMount } from "solid-js";
import { css } from "solid-styled-components";
import { MapOption } from "solid-effect";
import { cn } from "~/lib/cn";

import { DragLocationHistory } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";
import { draggable } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";

import Lozenge from "../Lozenge";
import * as Property from "./Property";

import * as Panel from "./Panel";

const getPanel = (tree: Panel.PanelTree, panelId: Panel.PanelId) =>
  Panel.getPanel(tree, { panelId }).pipe(Effect.runSync);

export type RenderPanelPillProps = {
  tree: Panel.PanelTree;
  setTree: Panel.SetPanelTree;

  selectedId: () => Option.Option<Panel.PanelId>;
  selectPanel: (id: Panel.PanelId) => void;

  panelId: () => Panel.PanelId;
  indent: number;
};

export const RenderPanelPill = (props: RenderPanelPillProps) => {
  const panel = () => getPanel(props.tree, props.panelId());

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
  tree: Panel.PanelTree;
  setTree: Panel.SetPanelTree;

  panelId: () => Panel.PanelId;
  selectPanel: (id: Panel.PanelId) => void;
  deselectPanel: () => void;
};

const PanelInspector = (props: PanelInspectorProps) => {
  const panel = () => getPanel(props.tree, props.panelId());

  return (
    <div class="font-mono">
      <Property.PropertyEditor showHeader={true}>
        <Property.StringProperty
          key="Debug name"
          value={panel().dbgName}
          onUpdate={(newValue) => {
            Panel.update(props.setTree, {
              panelId: panel().id,
              props: {
                dbgName: newValue,
              },
            }).pipe(Effect.runSync);
          }}
        />

        <Property.ButtonProperty
          key="Delete panel"
          onClick={Option.getOrUndefined(
            Option.map(
              panel().parent,
              (parentId) => () =>
                Effect.runSync(
                  Effect.gen(function* () {
                    const panelId = panel().id;
                    props.deselectPanel();
                    yield* Panel.deletePanel(props.setTree, { panelId });
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
            Panel.getPanel(props.tree, { panelId: id }).pipe(
              Effect.map((panel) => panel.dbgName),
              Effect.runSync,
            ),
          ).pipe(Option.getOrElse(() => "null"))}
        </Property.ButtonProperty>

        <Property.ArrayProperty
          key="Children"
          items={Array.from(panel().children).map((id) =>
            Panel.getPanel(props.tree, { panelId: id }).pipe(
              Effect.map((panel) => panel),
              Effect.runSync,
            ),
          )}
          preview={(item) => `'${item.dbgName}'`}
          render={(item) => (
            <Lozenge
              class="font-mono min-w-8 h-full p-0 border-1 cursor-pointer"
              color="aqua"
              interactive
              onClick={() => props.selectPanel(item.id)}
            >
              {item.dbgName}
            </Lozenge>
          )}
        />

        <Property.EnumProperty
          key="Layout"
          value={panel().layout}
          options={["vertical", "horizontal"]}
          onChange={(value) => {
            Panel.update(props.setTree, {
              panelId: panel().id,
              props: {
                layout: value as Panel.PanelLayout,
              },
            }).pipe(Effect.runSync);
          }}
        />

        <Property.StringProperty
          key="Percent of parent"
          value={(panel().percentOfParent * 100).toString()}
          format={(str) => str + "%"}
          onUpdate={(update) => {
            const num = Order.clamp(Order.number)({
              minimum: 0,
              maximum: 100,
            })(parseFloat(update));

            Panel.update(props.setTree, {
              panelId: panel().id,
              props: {
                percentOfParent: Panel.Percent(num / 100),
              },
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
                  panelId: panel().id,
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
  tree: Panel.PanelTree;
  setTree: Panel.SetPanelTree;

  selectedId: () => Option.Option<Panel.PanelId>;
  setSelectedId: (id: Option.Option<Panel.PanelId>) => void;
};

const Inspector = (props: InspectorProps) => {
  let componentRef!: HTMLDivElement;
  let sidePanelRef!: HTMLDivElement;
  let dividerRef!: HTMLDivElement;

  const [startingWidth, setStartingWidth] = createSignal(400);

  const getResizeWidth = (location: DragLocationHistory): number => {
    const delta =
      location.current.input.clientY - location.initial.input.clientY;

    return Order.clamp(Order.number)({
      minimum: 0,
      maximum: componentRef.clientHeight,
    })(startingWidth() - delta);
  };

  onMount(() => {
    const dragCleanup = draggable({
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

    onCleanup(() => {
      dragCleanup();
    });
  });

  return (
    <div ref={componentRef} class="flex flex-col w-auto h-full">
      <div
        class="font-mono grow p-2"
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
          "mt-auto h-[1px] bg-theme-border cursor-ns-resize relative",
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
        class="flex flex-col p-2 gap-2 overflow-auto"
        style={{
          "--local-starting-width": `${startingWidth()}px`,
          height: `var(--local-resizing-width, var(--local-starting-width))`,
        }}
      >
        <Lozenge
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
