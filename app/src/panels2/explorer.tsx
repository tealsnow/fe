import "../clamp";

import clsx from "clsx";
import { createSignal, For, onMount, Show } from "solid-js";
import { css } from "solid-styled-components";
import Lozenge from "../Lozenge";

import { DragLocationHistory } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";
import { draggable } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";

import {
  PanelEvent,
  PanelEventEmitter,
  PanelId,
  panels,
  PanelTreeStore,
} from "./panel";
import { getIntrinsicMinWidth } from "../getIntrinsicSize";

export type RenderPanelPillProps = {
  treeStore: PanelTreeStore;
  emitEvent: PanelEventEmitter;
  selectedId: PanelId | null;

  panelId: PanelId;
  indent: number;
};

export const RenderPanelPill = (props: RenderPanelPillProps) => {
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

            props.emitEvent(PanelEvent.select({ id: props.panelId }));
          }}
        >
          {panel.dbgName}
        </Lozenge>
      </div>

      <div class="flex flex-col">
        <For each={panel.children}>
          {(panelId) => {
            return (
              <RenderPanelPill
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

export type InspectProps = {
  tree: PanelTreeStore;
  panelId: PanelId;
  emitEvent: PanelEventEmitter;
};

export const Inspect = (props: InspectProps) => {
  const [newChildName, setNewChildName] = createSignal("");

  const deletePanel = () =>
    props.emitEvent(PanelEvent.delete({ id: props.panelId }));

  const panel = () => props.tree.value[props.panelId];

  const addChild = () => {
    const childName = newChildName().trim();
    if (childName.length === 0) return;

    const childId = panels.newPanelNode(props.tree, { dbgName: childName });
    props.emitEvent(PanelEvent.addChild({ id: props.panelId, childId }));
    setNewChildName("");
  };

  return (
    <div class="flex flex-col gap-2">
      <div class="flex flex-row gap-1 items-baseline">
        Selected:
        <Lozenge class="font-mono min-w-10" color="blue">
          {panel().dbgName}
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
            props.emitEvent(
              PanelEvent.delete({ id: PanelId("does not exist") }),
            );
          }}
        >
          delete fake
        </Lozenge>
      </div>
      Children:
      <div class="flex flex-row pl-6">
        <ul class="flex flex-col gap-1 list-disc">
          <For each={panel().children}>
            {(childId) => (
              <li>
                <Lozenge
                  class="font-mono min-w-10"
                  color="aqua"
                  interactive
                  onClick={() => {
                    props.emitEvent(PanelEvent.select({ id: childId }));
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
      <div class="flex flex-row gap-2 items-center">
        Layout:
        <Lozenge
          color="yellow"
          interactive
          highlighted={panel().layout === "vertical"}
          onClick={() =>
            props.emitEvent(
              PanelEvent.update({
                id: props.panelId,
                props: {
                  layout: "vertical",
                },
              }),
            )
          }
        >
          Vertical
        </Lozenge>
        <Lozenge
          color="yellow"
          interactive
          highlighted={panel().layout === "horizontal"}
          onClick={() =>
            props.emitEvent(
              PanelEvent.update({
                id: props.panelId,
                props: {
                  layout: "horizontal",
                },
              }),
            )
          }
        >
          Horizontal
        </Lozenge>
      </div>
      <div>
        Percent of parent: {(panel().percentOfParent * 100).toFixed(2)}%
      </div>
    </div>
  );
};

export type PanelsExplorerProps = {
  treeStore: PanelTreeStore;

  root: PanelId;
  selectedId: PanelId | null;

  emitEvent: PanelEventEmitter;
};

export const PanelsExplorer = (props: PanelsExplorerProps) => {
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
        onClick={() => props.emitEvent(PanelEvent.select({ id: null }))}
      >
        <RenderPanelPill
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
  );
};

export default PanelsExplorer;
