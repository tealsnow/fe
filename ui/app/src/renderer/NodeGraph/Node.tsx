import { VoidComponent, createEffect } from "solid-js";

import { Data } from "effect";

import cn from "~/lib/cn";
import UUID from "~/lib/UUID";
import { createElementSize, ElementSize } from "~/lib/createElementSize";

import { ColorKind } from "~/ui/Theme";

import { GridSize } from "./Config";
import { Coords } from "./coords";

export type Node = {
  id: UUID;
  coords: Coords;
  title: string;
  content: VoidComponent;
  color: ColorKind;
};
export const Node = ({ ...params }: Omit<Node, "id">): Node =>
  Data.case<Node>()({
    id: UUID.make(),
    ...params,
  });

export const RenderNode: VoidComponent<{
  node: Node;
  selected: () => boolean;
  snapNodeSizesToGrid: () => boolean;
  beginDragging: (ev: MouseEvent) => void;
  sized: (size: ElementSize) => void;
  onMouseDown: (ev: MouseEvent) => void;
  onHoverIn: (opts: { titlebar: boolean }) => void;
  onHoverOut: () => void;
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
  createEffect(() => {
    props.sized(size());
  });

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
        props.onHoverIn({ titlebar: false });
      }}
      onMouseLeave={() => {
        props.onHoverOut();
      }}
    >
      <div
        ref={titleRef}
        class="border-b whitespace-nowrap px-1 py-0.5 cursor-move"
        style={{
          background: `var(--theme-colors-${props.node.color}-background)`,
          "border-color": `var(--theme-colors-${props.node.color}-border)`,
        }}
        onMouseDown={(ev) => {
          props.beginDragging(ev);
        }}
        onMouseEnter={() => {
          props.onHoverIn({ titlebar: true });
        }}
      >
        {props.node.title}
      </div>
      <div
        class="p-1 min-w-0 size-full flex flex-col items-center gap-0.5"
        onMouseEnter={() => {
          props.onHoverIn({ titlebar: false });
        }}
      >
        {(() => {
          const Dot: VoidComponent<{ kind: "input" | "output" }> = (props) => {
            return (
              <div
                class={cn(
                  "size-2.5 rounded-full border absolute top-[50%] -translate-y-1/2 cursor-pointer",
                  props.kind === "input"
                    ? "bg-theme-colors-blue-base -left-2.5"
                    : "bg-theme-colors-green-base -right-2.5",
                )}
              />
            );
          };

          return (
            <>
              {/*<pre>
                [{props.node.coords[0]}, {props.node.coords[1]}]
              </pre>*/}

              <div class="relative flex w-full px-1">
                <span class="w-full text-right">output</span>
                {/*<div class="size-2 rounded-xl bg-theme-colors-green-base border absolute -right-2 top-[50%] -translate-y-1/2 cursor-pointer" />*/}
                <Dot kind="output" />
              </div>

              <div class="relative flex w-full px-1">
                <span class="w-full text-left">input</span>
                {/*<div class="size-2 rounded-xl bg-theme-colors-blue-base border absolute -left-2 top-[50%] -translate-y-1/2 cursor-pointer" />*/}
                <Dot kind="input" />
              </div>
            </>
          );
        })()}
      </div>
    </div>
  );
};
