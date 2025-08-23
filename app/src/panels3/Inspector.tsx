import { Effect, Option } from "effect";
import {
  Accessor,
  createEffect,
  createMemo,
  createSignal,
  For,
  onMount,
  Show,
} from "solid-js";
import { css } from "solid-styled-components";
import clsx from "clsx";
import { MapOption } from "solid-effect";

import { DragLocationHistory } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";
import { draggable } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";

import Lozenge from "../Lozenge";
import * as Property from "./Property";

import { getIntrinsicMinWidth } from "../getIntrinsicSize";

import * as Panel from "./Panel";

const getPanel = (treeStore: Panel.PanelTreeStore, panelId: Panel.PanelId) =>
  Panel.getPanel(treeStore.value, { panelId }).pipe(Effect.runSync);

export type RenderPanelPillProps = {
  treeStore: Panel.PanelTreeStore;
  selectedId: Option.Option<Panel.PanelId>;
  selectPanel: (id: Panel.PanelId) => void;

  panelId: Accessor<Panel.PanelId>;
  indent: number;
};

export const RenderPanelPill = (props: RenderPanelPillProps) => {
  // const panel = () => getPanel(props.treeStore, props.panelId());
  // const panel = createMemo(() => getPanel(props.treeStore, props.panelId()));

  // const panel_ = getPanel(props.treeStore, props.panelId());
  // const panel = () => panel_;

  // const panel = () => getPanel(props.treeStore, props.panelId());

  // const dbgName = () => panel().dbgName;

  const panel = () => props.treeStore.value.nodes[props.panelId()];

  // const dbgName = () => props.treeStore.value.nodes[props.panelId()].dbgName;
  const dbgName = props.treeStore.value.nodes[props.panelId()].dbgName;

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
          {/*{panel().dbgName}*/}
          {/*{dbgName()}*/}
          {dbgName}
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
  treeStore: Panel.PanelTreeStore;
  panelId: Panel.PanelId;
  selectPanel: (id: Panel.PanelId) => void;
};

const PanelInspector2 = (props: PanelInspector2Props) => {
  const panel = () => getPanel(props.treeStore, props.panelId);

  return (
    <>
      <Property.PropertyEditor
        properties={[
          <Property.Property
            key="Selected"
            value={
              // <Lozenge class="font-mono min-w-10" color="blue">
              //   {panel().dbgName}
              // </Lozenge>
              panel().dbgName
            }
          />,
          <Property.StringProperty
            key="Debug name"
            value={panel().dbgName}
            onUpdate={(newValue) => {
              // console.debug("new value:", newValue);
              Panel.update(props.treeStore, {
                panelId: props.panelId,
                props: {
                  dbgName: newValue,
                },
              }).pipe(Effect.runSync);
            }}
          />,

          <Property.Property
            key="Parent"
            value={Option.map(panel().parent, (id) =>
              Panel.getPanel(props.treeStore.value, { panelId: id }).pipe(
                Effect.map((panel) => panel.dbgName),
                Effect.runSync,
              ),
            ).pipe(Option.getOrElse(() => "null"))}
          />,
          // {
          //   key: "Selected",
          //   value: panel().dbgName,
          // },
          // {
          //   key: "Parent",
          //   value: () =>
          //     Option.map(panel().parent, (id) =>
          //       Panel.getPanel(props.treeStore.value, { panelId: id }).pipe(
          //         Effect.map((panel) => panel.dbgName),
          //         Effect.runSync,
          //       ),
          //     ).pipe(Option.getOrElse(() => "null")),
          // },
        ]}
      />
    </>
  );
};

type PanelInspectorProps = {
  treeStore: Panel.PanelTreeStore;
  panelId: Panel.PanelId;
  selectPanel: (id: Panel.PanelId) => void;
};

const PanelInspector = (props: PanelInspectorProps) => {
  const panel = () => getPanel(props.treeStore, props.panelId);

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
            const parent = () => getPanel(props.treeStore, parentId());
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
              const child = () => getPanel(props.treeStore, childId);
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
          treeStore={props.treeStore}
          panelId={props.panelId}
          selectPanel={props.selectPanel}
        />
      </div>
    </div>
  );
};

export type InspectorProps = {
  treeStore: Panel.PanelTreeStore;
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

    const min = getIntrinsicMinWidth(sidePanelRef);
    const max = componentRef.clientWidth * 0.75;

    return Math.clamp(startingWidth() - delta, min, max);
  };

  onMount(() => {
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
    <div ref={componentRef} class="flex flex-row w-auto h-full">
      <div
        class="font-mono grow h-full p-2"
        // onClick={() => props.emitEvent(PanelEvent.select({ id: null }))}
        onClick={() => props.selectPanel(Option.none())}
      >
        <RenderPanelPill
          treeStore={props.treeStore}
          selectedId={props.selectedId}
          selectPanel={(id) => props.selectPanel(Option.some(id))}
          panelId={() => props.treeStore.value.root}
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
              treeStore={props.treeStore}
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
