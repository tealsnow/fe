import { Effect, Option, Order } from "effect";
import {
  Accessor,
  createEffect,
  createMemo,
  createSignal,
  For,
  onCleanup,
  onMount,
  Show,
} from "solid-js";
import { css } from "solid-styled-components";
import { MapOption } from "solid-effect";
import { cn } from "~/lib/cn";

import { DragLocationHistory } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";
import { draggable } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";

import Lozenge from "../Lozenge";
import * as Property from "./Property";

import { getIntrinsicMinWidth } from "../getIntrinsicSize";

import * as Panel from "./Panel";

const getPanel = (tree: Panel.PanelTree, panelId: Panel.PanelId) =>
  Panel.getPanel(tree, { panelId }).pipe(Effect.runSync);

export type RenderPanelPillProps = {
  tree: Panel.PanelTree;
  selectedId: Option.Option<Panel.PanelId>;
  selectPanel: (id: Panel.PanelId) => void;

  panelId: Accessor<Panel.PanelId>;
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
          highlighted={Option.getOrNull(props.selectedId) === props.panelId()}
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

type PanelInspector2Props = {
  tree: Panel.PanelTree;
  setTree: Panel.SetPanelTree;
  panelId: Panel.PanelId;
  selectPanel: (id: Panel.PanelId) => void;
};

const PanelInspector2 = (props: PanelInspector2Props) => {
  const panel = () => getPanel(props.tree, props.panelId);

  return (
    <div class="font-mono">
      <Property.PropertyEditor>
        <Property.StringProperty
          key="Debug name"
          value={panel().dbgName}
          onUpdate={(newValue) => {
            // console.debug("new value:", newValue);
            Panel.update(props.setTree, {
              panelId: props.panelId,
              props: {
                dbgName: newValue,
              },
            }).pipe(Effect.runSync);
          }}
        />
        <Property.StringProperty
          key="Parent"
          value={Option.map(panel().parent, (id) =>
            Panel.getPanel(props.tree, { panelId: id }).pipe(
              Effect.map((panel) => panel.dbgName),
              Effect.runSync,
            ),
          ).pipe(Option.getOrElse(() => "null"))}
          onClick={Option.map(
            panel().parent,
            (id) => () => props.selectPanel(id),
          ).pipe(Option.getOrUndefined)}
        />
        <Property.StringProperty
          key="Percent of parent"
          value={(panel().percentOfParent * 100).toString()}
          format={(str) => str + "%"}
          onUpdate={(update) => {
            const num: number = parseFloat(update);
            if (num < 0 || num > 100) return;
            if (!isNaN(num)) {
              Panel.update(props.setTree, {
                panelId: props.panelId,
                props: {
                  percentOfParent: Panel.Percent(num / 100),
                },
              }).pipe(Effect.runSync);
            }
          }}
        />

        <Show when={panel().children.length !== 0}>
          <Property.StringProperty
            key="Children % valid"
            value={Panel.validateChildrenSizes(props.tree, {
              panelId: props.panelId,
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
              Effect.runSync,
            )}
          />
        </Show>
      </Property.PropertyEditor>

      {/*<div class="w-full border-2 flex flex-col">
        <div class="w-full border flex flex-row">
          <div class="w-full">Debug name</div>

          <div class="w-full">{panel().dbgName}</div>
        </div>
      </div>*/}
    </div>
  );
};

type PanelInspectorProps = {
  tree: Panel.PanelTree;
  setTree: Panel.SetPanelTree;
  panelId: Panel.PanelId;
  selectPanel: (id: Panel.PanelId) => void;
};

const PanelInspector = (props: PanelInspectorProps) => {
  const panel = () => getPanel(props.tree, props.panelId);

  return (
    <div class="flex flex-col gap-2">
      <div class="flex flex-row gap-1 items-baseline">
        Selected:
        <Lozenge class="font-mono min-w-10" color="blue">
          {panel().dbgName}
        </Lozenge>
      </div>
      <div class="flex flex-row gap-1 items-baseline">
        Parent:
        <MapOption
          on={panel().parent}
          fallback={
            <Lozenge class="font-mono min-w-10" color="red">
              null
            </Lozenge>
          }
        >
          {(parentId) => {
            const parent = () => getPanel(props.tree, parentId());
            return (
              <Lozenge
                class="font-mono min-w-10"
                color="purple"
                interactive
                onClick={() => props.selectPanel(parentId())}
              >
                {parent().dbgName}
              </Lozenge>
            );
          }}
        </MapOption>
      </div>
      {/*<div class="flex flex-row gap-2">
        <Lozenge
          color="red"
          interactive
          // onClick={deletePanel}
        >
          delete
        </Lozenge>
        <Lozenge
          color="red"
          interactive
          onClick={() => {
            // props.emitEvent(
            //   PanelEvent.delete({ id: PanelId("does not exist") }),
            // );
          }}
        >
          delete fake
        </Lozenge>
      </div>*/}
      Children:
      <div class="flex flex-row pl-6">
        <ul class="flex flex-col gap-1 list-disc">
          <For each={panel().children}>
            {(childId) => {
              const child = () => getPanel(props.tree, childId);
              return (
                <li>
                  <Lozenge
                    class="font-mono min-w-10"
                    color="aqua"
                    interactive
                    onClick={() => props.selectPanel(childId)}
                  >
                    {child().dbgName}
                  </Lozenge>
                </li>
              );
            }}
          </For>
        </ul>
      </div>
      {/*<div class="flex flex-row gap-2">
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
      </div>*/}
      <div class="flex flex-row gap-2 items-center">
        Layout:
        <Lozenge
          color="yellow"
          interactive
          highlighted={panel().layout === "vertical"}
          // onClick={() =>
          //   props.emitEvent(
          //     PanelEvent.update({
          //       id: props.panelId,
          //       props: {
          //         layout: "vertical",
          //       },
          //     }),
          //   )
          // }
        >
          Vertical
        </Lozenge>
        <Lozenge
          color="yellow"
          interactive
          highlighted={panel().layout === "horizontal"}
          // onClick={() =>
          //   props.emitEvent(
          //     PanelEvent.update({
          //       id: props.panelId,
          //       props: {
          //         layout: "horizontal",
          //       },
          //     }),
          //   )
          // }
        >
          Horizontal
        </Lozenge>
      </div>
      <div>
        Percent of parent: {(panel().percentOfParent * 100).toFixed(2)}%
      </div>
      <div class="w-full border-t border-theme-border pt-3">
        <PanelInspector2
          tree={props.tree}
          setTree={props.setTree}
          panelId={props.panelId}
          selectPanel={props.selectPanel}
        />
      </div>
    </div>
  );
};

export type InspectorProps = {
  tree: Panel.PanelTree;
  setTree: Panel.SetPanelTree;
  selectedId: Option.Option<Panel.PanelId>;
  selectPanel: (id: Option.Option<Panel.PanelId>) => void;
};

const Inspector = (props: InspectorProps) => {
  let componentRef!: HTMLDivElement;
  let sidePanelRef!: HTMLDivElement;
  let dividerRef!: HTMLDivElement;

  const [startingWidth, setStartingWidth] = createSignal(400);

  const getResizeWidth = (location: DragLocationHistory): number => {
    const delta =
      location.current.input.clientX - location.initial.input.clientX;

    // const min = getIntrinsicMinWidth(sidePanelRef);
    // const max = componentRef.clientWidth * 0.75;

    // return Math.clamp(startingWidth() - delta, min, max);

    return Order.clamp(Order.number)({
      minimum: 0,
      maximum: componentRef.clientWidth,
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
    <div ref={componentRef} class="flex flex-row w-auto h-full">
      <div
        class="font-mono grow h-full p-2"
        // onClick={() => props.emitEvent(PanelEvent.select({ id: null }))}
        onClick={() => props.selectPanel(Option.none())}
      >
        <RenderPanelPill
          tree={props.tree}
          selectedId={props.selectedId}
          selectPanel={(id) => props.selectPanel(Option.some(id))}
          panelId={() => props.tree.root}
          indent={0}
        />
      </div>

      <div
        ref={dividerRef}
        class={cn(
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
        class="flex flex-col p-2 gap-2 overflow-clip"
        style={{
          "--local-starting-width": `${startingWidth()}px`,
          width: `var(--local-resizing-width, var(--local-starting-width))`,
        }}
      >
        {/*<Lozenge
          color="pink"
          interactive
          onClick={() => {
            for (const [id, panel] of Object.entries(props.treeStore.value)) {
              console.log("id:", id, ",", "dbgName:", panel.dbgName);
            }
          }}
        >
          Print all panels
        </Lozenge>*/}

        <MapOption on={props.selectedId}>
          {(selectedId) => (
            <PanelInspector
              tree={props.tree}
              setTree={props.setTree}
              panelId={selectedId()}
              selectPanel={(id) => props.selectPanel(Option.some(id))}
            />
          )}
        </MapOption>
      </div>
    </div>
  );
};

export default Inspector;
