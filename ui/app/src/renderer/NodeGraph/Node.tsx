import {
  For,
  Match,
  Switch,
  VoidComponent,
  createEffect,
  onMount,
} from "solid-js";

import { Data } from "effect";

import cn from "~/lib/cn";
import UUID from "~/lib/UUID";
import { createElementSize, ElementSize } from "~/lib/createElementSize";

import { ColorKind } from "~/ui/Theme";

import { GridSize } from "./Config";
import { Coords } from "./coords";
import { PickPartial } from "~/lib/type_helpers";

export type Socket = Data.TaggedEnum<{
  Input: {
    id: UUID;
    name: string;
  };
  Output: {
    id: UUID;
    name: string;
  };
}>;

export type Input = Data.TaggedEnum.Value<Socket, "Input">;
export type Output = Data.TaggedEnum.Value<Socket, "Output">;

export const Input = (
  params: PickPartial<Omit<Input, "_tag">, "id">,
): Input => ({
  _tag: "Input",
  id: UUID.make(),
  ...params,
});

export const Output = (
  params: PickPartial<Omit<Output, "_tag">, "id">,
): Output => ({
  _tag: "Output",
  id: UUID.make(),
  ...params,
});

export type Connection = {
  from: { node: UUID; socket: UUID };
  to: { node: UUID; socket: UUID };
};

export type Node = {
  id: UUID;
  lastTouchedTime: number | null;
  coords: Coords;
  title: string;
  color: ColorKind;
  inputs: Input[];
  outputs: Output[];
};
export const Node = ({
  inputs = [],
  outputs = [],
  ...params
}: PickPartial<
  Omit<Node, "lastTouchedTime">,
  "inputs" | "outputs" | "id"
>): Node =>
  Data.case<Node>()({
    id: UUID.make(),
    lastTouchedTime: null,
    inputs,
    outputs,
    ...params,
  });

export const RenderNode: VoidComponent<{
  node: Node;
  selected: () => boolean;
  snapNodeSizesToGrid: () => boolean;
  beginDragging: (ev: MouseEvent) => void;
  beginConnection: (id: UUID, ev: MouseEvent) => void;
  sized: (size: ElementSize) => void;
  socketRef: (id: UUID, ref: HTMLDivElement) => void;
  onMouseDown: (ev: MouseEvent) => void;
  onHoverChange: (opts: { titlebar: boolean } | null) => void;
  onHoverSocketChange: (id: UUID | null) => void;
}> = (props) => {
  const [size, setSizeRef] = createElementSize();
  let titleRef!: HTMLDivElement;

  const ceilToGrid = (v: number): number =>
    Math.ceil((v + 2) / GridSize) * GridSize;

  const snapSize = (size: number): string => {
    if (!props.snapNodeSizesToGrid() || size === 0) return "auto";
    else return `${ceilToGrid(size)}px`;
  };

  const snappedWidth = (): string => snapSize(size().width);
  const snappedHeight = (): string => snapSize(size().height);

  // inform parent of size whenever set
  createEffect(() => props.sized(size()));

  return (
    <div
      ref={setSizeRef}
      tabIndex="0"
      class={cn(
        "absolute border rounded-sm bg-theme-background/75 max-w-80 inline-flex flex-col box-border drop-shadow-xl outline-offset-0 focus:outline-1 cursor-default",
        props.selected() && "outline-1",
      )}
      style={{
        transform: `translate(
          ${props.node.coords[0]}px,
          ${props.node.coords[1]}px
        )`,

        width: snappedWidth(),
        height: snappedHeight(),

        "border-color": `var(--theme-colors-${props.node.color}-border)`,
        "outline-color": `var(--theme-colors-${props.node.color}-border)`,
      }}
      onMouseDown={(ev) => {
        ev.stopPropagation();
        props.onMouseDown(ev);
      }}
      onMouseEnter={() => {
        props.onHoverChange({ titlebar: false });
      }}
      onMouseLeave={() => {
        props.onHoverChange(null);
      }}
    >
      <div
        ref={titleRef}
        class="border-b whitespace-nowrap px-1 min-h-6 max-h-6 flex items-center cursor-move"
        style={{
          background: `var(--theme-colors-${props.node.color}-background)`,
          "border-color": `var(--theme-colors-${props.node.color}-border)`,
        }}
        onMouseDown={(ev) => {
          props.beginDragging(ev);
        }}
        onMouseEnter={() => {
          props.onHoverChange({ titlebar: true });
        }}
      >
        {props.node.title}
      </div>
      <div
        class="p-1 min-w-0 size-full flex flex-col items-center justify-center gap-0.5"
        onMouseEnter={() => {
          props.onHoverChange({ titlebar: false });
        }}
      >
        {(() => {
          const socketRef = (): ((id: UUID, ref: HTMLDivElement) => void) =>
            props.socketRef;
          const beginConnection = (): ((id: UUID, ev: MouseEvent) => void) =>
            props.beginConnection;
          const onHoverSocketChange = (): ((id: UUID | null) => void) =>
            props.onHoverSocketChange;

          const Socket: VoidComponent<{
            id: UUID;
            kind: "input" | "output";
          }> = (props) => {
            let ref!: HTMLDivElement;
            onMount(() => socketRef()(props.id, ref));

            return (
              <div
                ref={ref}
                class={cn(
                  "size-2.5 rounded-full border absolute top-[50%] -translate-y-1/2 cursor-pointer",
                  props.kind === "input"
                    ? "bg-theme-colors-blue-base -left-2.5"
                    : "bg-theme-colors-green-base -right-2.5",
                )}
                onMouseDown={(ev) => {
                  beginConnection()(props.id, ev);
                }}
                onMouseOver={() => {
                  onHoverSocketChange()(props.id);
                }}
                onMouseLeave={() => {
                  onHoverSocketChange()(null);
                }}
              />
            );
          };

          const IO: VoidComponent<{
            kind: "input" | "output";
            name: string;
            id: UUID;
          }> = (props) => {
            return (
              <div class="relative h-6 flex w-full px-1 items-center">
                <Switch>
                  <Match when={props.kind === "input"}>
                    <span class="w-full text-left">{props.name}</span>
                    <Socket id={props.id} kind="input" />
                  </Match>
                  <Match when={props.kind === "output"}>
                    <span class="w-full text-right">{props.name}</span>
                    <Socket id={props.id} kind="output" />
                  </Match>
                </Switch>
              </div>
            );
          };

          return (
            <>
              <For each={props.node.inputs}>
                {(input) => <IO kind="input" name={input.name} id={input.id} />}
              </For>
              <For each={props.node.outputs}>
                {(output) => (
                  <IO kind="output" name={output.name} id={output.id} />
                )}
              </For>
            </>
          );
        })()}
      </div>
    </div>
  );
};
