import {
  For,
  Match,
  Switch,
  VoidComponent,
  createEffect,
  onMount,
} from "solid-js";

import { Brand, Data } from "effect";

import cn from "~/lib/cn";
import UUID from "~/lib/UUID";
import { createElementSize, ElementSize } from "~/lib/createElementSize";

import { ColorKind } from "~/ui/Theme";

import { GridSize } from "./Config";
import { Coords } from "./coords";
import { PickPartial } from "~/lib/type_helpers";

type NodeBrand = string & Brand.Brand<"NodeId">;
const NodeBrand = Brand.nominal<NodeBrand>();

export const NodeId = Brand.all(NodeBrand, UUID);
export type NodeId = Brand.Brand.FromConstructor<typeof NodeId>;

export type Node = {
  id: NodeId;
  lastTouchedTime: number | null;
  coords: Coords;
  title: string;
  color: ColorKind;
  inputs: SocketInput[];
  outputs: SocketOutput[];
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
    id: NodeId(UUID.make()),
    lastTouchedTime: null,
    inputs,
    outputs,
    ...params,
  });

type SocketBrand = string & Brand.Brand<"SocketId">;
const SocketBrand = Brand.nominal<SocketBrand>();

export const SocketId = Brand.all(SocketBrand, UUID);
export type SocketId = Brand.Brand.FromConstructor<typeof SocketId>;

export type SocketKind = Data.TaggedEnum<{
  Input: {};
  Output: {};
}>;
export namespace SocketKind {
  export type Input = Data.TaggedEnum.Value<SocketKind, "Input">;
  export type Output = Data.TaggedEnum.Value<SocketKind, "Output">;

  export const Input = (params: Omit<Input, "_tag">): Input => ({
    _tag: "Input",
    ...params,
  });

  export const Output = (params: Omit<Output, "_tag">): Output => ({
    _tag: "Output",
    ...params,
  });
}

export type Socket = {
  id: SocketId;
  name: string;
  kind: SocketKind;
};
export function Socket(params: PickPartial<SocketInput, "id">): SocketInput;
export function Socket(params: PickPartial<SocketOutput, "id">): SocketOutput;
export function Socket(params: PickPartial<Socket, "id">): Socket {
  return {
    id: SocketId(UUID.make()),
    ...params,
  };
}

export type SocketInput = Socket & { kind: SocketKind.Input };
export type SocketOutput = Socket & { kind: SocketKind.Output };

export type Connection = {
  from: { node: NodeId; socket: SocketId };
  to: { node: NodeId; socket: SocketId };
};
export const Connection = Data.case<Connection>();

export const RenderNode: VoidComponent<{
  node: Node;
  selected: () => boolean;
  snapNodeSizesToGrid: () => boolean;
  beginDragging: (ev: MouseEvent) => void;
  beginConnection: (id: SocketId, ev: MouseEvent) => void;
  sized: (size: ElementSize) => void;
  socketRef: (id: SocketId, ref: HTMLDivElement) => void;
  onMouseDown: (ev: MouseEvent) => void;
  onHoverChange: (opts: { titlebar: boolean } | null) => void;
  onHoverSocketChange: (id: SocketId | null) => void;
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
          const socketRef = (): ((id: SocketId, ref: HTMLDivElement) => void) =>
            props.socketRef;
          const beginConnection = (): ((
            id: SocketId,
            ev: MouseEvent,
          ) => void) => props.beginConnection;
          const onHoverSocketChange = (): ((id: SocketId | null) => void) =>
            props.onHoverSocketChange;

          const Socket: VoidComponent<{
            id: SocketId;
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
            id: SocketId;
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
