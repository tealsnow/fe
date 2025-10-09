import {
  Accessor,
  Setter,
  For,
  JSX,
  Show,
  VoidComponent,
  createEffect,
  createSignal,
} from "solid-js";
import { createStore, produce } from "solid-js/store";
import { makePersisted } from "@solid-primitives/storage";
import { DocumentEventListener } from "@solid-primitives/event-listener";

import { Data, Match, Order } from "effect";

import cn from "~/lib/cn";
import UUID from "~/lib/UUID";
import { createElementSize, ElementSize } from "~/lib/createElementSize";

import { ColorKind } from "~/ui/Theme";

import Icon from "~/ui/components/Icon";
import Button from "~/ui/components/Button";
import Switch from "./ui/components/Switch";
import Select from "./ui/components/Select";
import Collapsible from "./ui/components/Collapsible";
import Label from "./ui/components/Label";
import KeyboardKey from "./ui/components/KeyboardKey";
import MouseButton from "./ui/components/MouseButton";

const GridSize = 10;

const ZoomMinMax = {
  min: 0.2,
  max: 5,
};

type Coords = [number, number];

const SnapKind = ["none", "1s", "5s", "disabled"] as const;
type SnapKind = (typeof SnapKind)[number];

const coordsSnapToGrid = ([x, y]: Coords, kind: SnapKind): Coords =>
  Match.value(kind).pipe(
    Match.withReturnType<Coords>(),
    Match.whenOr("none", "disabled", () => [x, y]),
    Match.when("1s", () => [
      Math.round(x / GridSize) * GridSize,
      Math.round(y / GridSize) * GridSize,
    ]),
    Match.when("5s", () => [
      Math.round(x / (GridSize * 5)) * GridSize * 5,
      Math.round(y / (GridSize * 5)) * GridSize * 5,
    ]),
    Match.exhaustive,
  );

type SnapConfig = {
  default: SnapKind;
  ctrl: SnapKind;
  shift: SnapKind;
  ctrlShift: SnapKind;
};

const kindForSnapConfig = (
  config: SnapConfig,
  mods: { ctrl: boolean; shift: boolean },
): SnapKind =>
  Match.value(mods).pipe(
    Match.withReturnType<SnapKind>(),
    Match.when({ ctrl: true, shift: true }, () => config.ctrlShift),
    Match.when({ ctrl: true, shift: false }, () => config.ctrl),
    Match.when({ ctrl: false, shift: true }, () => config.shift),
    Match.when({ ctrl: false, shift: false }, () => config.default),
    Match.exhaustive,
  );

type Node = {
  id: UUID;
  coords: Coords;
  title: string;
  content: VoidComponent;
  color: ColorKind;
};
const Node = ({ ...params }: Omit<Node, "id">): Node =>
  Data.case<Node>()({
    id: UUID.make(),
    ...params,
  });

/* IO:

store connections out of scope?
node id -> Connection {
  input id
  output id
}

InputID :: struct {
  node NodeID
  id UUID
}

Node :: struct {
  ...
  inputs []InputID
}

Input :: struct {
  type ...
}

Output :: struct {
  type ...
}

*/

/* Input (interaction):

Whats the best way we can generalize this?

The current state is an absolute mess and nightmare of spaghetti.
An abstraction would be highly beneficial here.

First though that comes to mind is to utilize the (yet non existent) modal
input system. Node editing can be its own super contextual mode, with sub modes.
But I'm getting ahead of myself.

As of right now, we have a few modes of input:
 - [ [space+lmb] or [mmb] (on canvas) ] or trackpad pan (anywhere) -> pan
   - ctrl,shift,ctrlShift -> modify snapping
 - lmb (on node titlebar) -> move node
   - ctrl,shift,ctrlShift -> modify snapping
 - ctrl+scroll or trackpad pinch -> zoom
 - rmb+move up/down (on canvas) -> zoom

I think we can best thing of these as "layers" which are mostly mutually
exclusive.
Currently that is communicated by the input statusbar dynamically hiding and
showing modes of input based on the current state. This is done mostly
empirically, just by checking the if other inputs modes are active in a pretty
indirect manner. This is not helped either by the mess of signals for each
individual piece of information.

A general outline of what to do:
  - group logical bits of input information
  - provide some better heuristic for the current state/layer of input
  - maybe create an abstraction akin to the layer concept here
  - use this to provide good information to the user

*/

const NodeGraphTest: VoidComponent = () => {
  const [originOffset, setOriginOffset] = createSignal<Coords>([10, 10]);
  const [zoom, setZoom] = createSignal(1);

  const [dragStartPos, setDragStartPos] = createSignal<Coords>([0, 0]);
  const [draggingNode, setDraggingNode] = createSignal<{
    id: UUID;
    start: Coords;
  } | null>(null);
  const [panning, setPanning] = createSignal<Coords | null>(null);

  const [dragZoom, setDragZoom] = createSignal(false);

  const [panSnapConfig, setPanSnapConfig] = createSignal<SnapConfig>({
    default: "none",
    shift: "1s",
    ctrl: "5s",
    ctrlShift: "disabled",
  });

  const [nodeSnapConfig, setNodeSnapConfig] = createSignal<SnapConfig>({
    default: "1s",
    shift: "none",
    ctrl: "5s",
    ctrlShift: "disabled",
  });

  const [containerSize, setContainerSizeRef] = createElementSize();
  let containerRef!: HTMLDivElement;

  const [snapNodeSizesToGrid, setSnapNodeSizesToGrid] = createSignal(true);

  // @NOTE: do not set anything inside of the node directly.
  //   it goes through a <For> and thus looses reactivity below the node level
  const [nodes, setNodes] = createStore<Node[]>([
    Node({
      title: "some node",
      color: "blue",
      content: () => "some content",
      coords: [20, 100],
    }),
    Node({
      title: "another node",
      color: "green",
      content: () => "some content",
      coords: [220, 120],
    }),
  ]);

  // doesn't understand what makePersisted is
  // eslint-disable-next-line solid/reactivity
  const [sidebarOpen, setSidebarOpen] = makePersisted(createSignal(false), {
    name: "nodeGraph-sidebar-open",
    storage: localStorage,
  });

  const [gridStyle, setGridStyle] = makePersisted(
    // eslint-disable-next-line solid/reactivity
    createSignal<GridStyle>("grid_lines"),
    {
      name: "nodeGraph-gridStyle",
      storage: localStorage,
    },
  );

  const [mouseInside, setMouseInside] = createSignal(false);

  const [shiftDown, setShiftDown] = createSignal(false);
  const [ctrlDown, setCtrlDown] = createSignal(false);
  const [spaceDown, setSpaceDown] = createSignal(false);
  const [leftMouseButtonDown, setLeftMouseButtonDown] = createSignal(false);

  const handleZoom = (delta: number, [x, y]: Coords): void => {
    const oldZoom = zoom();

    const normalized = Math.sign(delta) * Math.min(Math.abs(delta) / 100, 1);
    const zoomSpeed = 0.15; // lower = slower, smoother
    const zoomFactor = 1 + normalized * zoomSpeed;

    const newZoom = Order.clamp(Order.number)({
      minimum: ZoomMinMax.min,
      maximum: ZoomMinMax.max,
    })(oldZoom * zoomFactor);

    const rect = containerRef.getBoundingClientRect();
    const mouseX = x - rect.left;
    const mouseY = y - rect.top;

    // world coords before zoom
    const [ox, oy] = originOffset();
    const worldX = (mouseX - ox) / oldZoom;
    const worldY = (mouseY - oy) / oldZoom;

    // new origin so mouse stays fixed in same world space
    const newOx = mouseX - worldX * newZoom;
    const newOy = mouseY - worldY * newZoom;

    setOriginOffset([newOx, newOy]);
    setZoom(newZoom);
  };

  const [nodeHovered, setNodeHovered] = createSignal<{
    titlebar: boolean;
  } | null>(null);

  return (
    <div class="size-full flex flex-col">
      <DocumentEventListener
        onKeydown={(ev) => {
          Match.value(ev.key).pipe(
            Match.when("Shift", () => setShiftDown(true)),
            Match.when("Control", () => setCtrlDown(true)),
            // eslint-disable-next-line solid/reactivity
            Match.when(" ", () => {
              setSpaceDown(true);
              if (mouseInside() && !containerRef.matches(":focus-within"))
                containerRef.focus();
            }),
            Match.orElse((key) => {
              console.log(`key down '${key}'`);
            }),
          );
        }}
        onKeyup={(ev) => {
          Match.value(ev.key).pipe(
            Match.when("Shift", () => setShiftDown(false)),
            Match.when("Control", () => setCtrlDown(false)),
            Match.when(" ", () => setSpaceDown(false)),
          );
        }}
        onMousedown={(ev) => {
          Match.value(ev.button).pipe(
            Match.when(0, () => setLeftMouseButtonDown(true)),
            // Match.when(1, () => "middle"),
            // Match.when(2, () => "right"),
          );
        }}
        onMouseup={(ev) => {
          Match.value(ev.button).pipe(
            Match.when(0, () => setLeftMouseButtonDown(false)),
            // Match.when(1, () => "middle"),
            // Match.when(2, () => "right"),
          );
        }}
      />

      <div class="h-7 border-b flex flex-row items-center px-1 gap-4 overflow-y-scroll no-scrollbar">
        <Button
          as={Icon}
          icon={
            sidebarOpen()
              ? "SidebarIndicatorEnabled"
              : "SidebarIndicatorDisabled"
          }
          variant="icon"
          size="icon"
          class="ml-auto rotate-270"
          highlighted={sidebarOpen()}
          onClick={() => setSidebarOpen((b) => !b)}
        />
      </div>

      <div class="flex flex-row-reverse size-full">
        <Show when={sidebarOpen()}>
          <div class="min-w-1/3 max-w-1/3 border-l flex flex-col [&>div]:p-2">
            <Settings
              class="h-2/3 border-b"
              snapNodeSizesToGrid={snapNodeSizesToGrid}
              setSnapNodeSizesToGrid={setSnapNodeSizesToGrid}
              gridStyle={gridStyle}
              setGridStyle={setGridStyle}
              panSnapConfig={panSnapConfig}
              setPanSnapConfig={setPanSnapConfig}
              nodeSnapConfig={nodeSnapConfig}
              setNodeSnapConfig={setNodeSnapConfig}
            />
            <div class="h-1/3 flex flex-col overflow-x-scroll">
              <h2 class="text-lg underline underline-offset-2">Dbg</h2>

              <div class="flex flex-row items-center gap-2">
                <pre>
                  offset: [{originOffset()[0].toFixed(2)},{" "}
                  {originOffset()[1].toFixed(2)}]
                </pre>
                <Button
                  size="small"
                  variant="outline"
                  onClick={() => setOriginOffset([0, 0])}
                >
                  reset
                </Button>
              </div>
              <pre>
                size: [{containerSize().width.toFixed(2)},{" "}
                {containerSize().height.toFixed(2)}]
              </pre>
              <div class="flex flex-row items-center gap-2">
                <pre>zoom: {zoom().toFixed(2)}</pre>
                <Button
                  size="small"
                  variant="outline"
                  onClick={() => setZoom(1)}
                >
                  reset
                </Button>
              </div>

              <pre>nodeHovered: {JSON.stringify(nodeHovered())}</pre>
            </div>
          </div>
        </Show>

        <div
          ref={(ref) => {
            setContainerSizeRef(ref);
            containerRef = ref;
          }}
          tabIndex="-1"
          class={cn(
            "size-full relative overflow-hidden focus:ring-0 focus:outline-0",
            spaceDown() && "cursor-grab",
            panning() && "cursor-grabbing",
            draggingNode() && "cursor-move",
            dragZoom() && "cursor-ns-resize",
          )}
          onWheel={(ev: WheelEvent) => {
            ev.preventDefault();

            if (ev.ctrlKey) {
              handleZoom(ev.deltaY * -8, [ev.clientX, ev.clientY]);
            } else {
              const speed = 0.2;
              const [ox, oy] = originOffset();
              const dx = ev.deltaX * speed;
              const dy = ev.deltaY * speed;

              if (ev.shiftKey) {
                setOriginOffset([ox - dy, oy]);
              } else {
                setOriginOffset([ox - dx, oy - dy]);
              }
            }
          }}
          onMouseDown={(ev) => {
            ev.preventDefault();

            const rightButton = 2;
            const middleButton = 1;

            if (ev.button === rightButton) {
              setDragZoom(true);
              setDragStartPos([ev.x, ev.y]);
            } else if (
              ev.button === middleButton ||
              (spaceDown() && draggingNode() === null)
            ) {
              setPanning(originOffset());
              setDragStartPos([ev.x, ev.y]);
            }
          }}
          onMouseMove={(ev) => {
            setMouseInside(true);

            if (dragZoom()) {
              containerRef.focus();

              const [startX, startY] = dragStartPos();
              const dy = ev.y - startY;

              const rect = containerRef.getBoundingClientRect();
              const centerX = rect.width / 2;
              const centerY = rect.height / 2;

              handleZoom(
                dy * -0.25,
                ev.ctrlKey ? [centerX, centerY] : [startX, startY],
              );
            } else if (draggingNode()) {
              const dragNode = draggingNode()!;

              // delta from where the drag started, adjusted to the zoom factor
              const [startX, startY] = dragStartPos();
              const dx = (ev.x - startX) / zoom();
              const dy = (ev.y - startY) / zoom();

              const [x, y] = dragNode.start;
              const newCoords: Coords = [x + dx, y + dy];

              const snapped = coordsSnapToGrid(
                newCoords,
                kindForSnapConfig(nodeSnapConfig(), {
                  ctrl: ev.ctrlKey,
                  shift: ev.shiftKey,
                }),
              );

              setNodes(
                (node) => node.id == dragNode.id,
                (node) => ({
                  ...node,
                  coords: snapped,
                }),
              );
            } else if (panning()) {
              containerRef.focus();

              // delta from where the drag started
              const [startX, startY] = dragStartPos();
              const dx = ev.x - startX;
              const dy = ev.y - startY;

              const [x, y] = panning()!;
              const [ox, oy] = [x + dx, y + dy];

              // convert offset from screen -> world -> snap -> back to screen
              const worldOffset: Coords = [ox / zoom(), oy / zoom()];
              const snappedWorldOffset = coordsSnapToGrid(
                worldOffset,
                kindForSnapConfig(panSnapConfig(), {
                  ctrl: ev.ctrlKey,
                  shift: ev.shiftKey,
                }),
              );
              const newOffset: Coords = [
                snappedWorldOffset[0] * zoom(),
                snappedWorldOffset[1] * zoom(),
              ];

              setOriginOffset(newOffset);
            }
          }}
          onMouseUp={() => {
            setPanning(null);
            setDraggingNode(null);
            setDragZoom(false);
          }}
          onMouseEnter={() => {
            setMouseInside(true);
          }}
          onMouseLeave={() => {
            setMouseInside(false);
            setPanning(null);
            setDraggingNode(null);
            setDragZoom(false);
          }}
        >
          <RenderGrid
            size={containerSize}
            originOffset={originOffset}
            gridStyle={gridStyle}
            zoom={zoom}
          />

          <Show when={dragZoom()}>
            {(() => {
              const rect = containerRef.getBoundingClientRect();
              return (
                <svg
                  class="absolute"
                  style={{
                    transform: `translate(
                      ${dragStartPos()[0] - rect.left - 8}px,
                      ${dragStartPos()[1] - rect.top - 8}px
                    )`,
                  }}
                  width="16"
                  height="16"
                  viewBox="0 0 100 100"
                >
                  <line
                    x1="15"
                    y1="50"
                    x2="85"
                    y2="50"
                    stroke="currentColor"
                    stroke-width="2"
                  />
                  <line
                    x1="50"
                    y1="15"
                    x2="50"
                    y2="85"
                    stroke="currentColor"
                    stroke-width="2"
                  />
                </svg>
              );
            })()}
          </Show>

          <div
            class={cn("absolute size-full overflow-visible z-10")}
            style={{
              transform: `
                translate(
                  ${originOffset()[0]}px,
                  ${originOffset()[1]}px
                )
                scale(${zoom()})
              `,
              "transform-origin": "0 0",
            }}
          >
            <div class="size-px bg-white absolute left-0 right-0" />

            <For each={nodes}>
              {(node, idx) => {
                return (
                  <RenderNode
                    node={node}
                    onTouch={() => {
                      // move the touched item last so it will render on top
                      setNodes(
                        produce((items) =>
                          items.push(items.splice(idx(), 1)[0]),
                        ),
                      );
                    }}
                    snapNodeSizesToGrid={snapNodeSizesToGrid}
                    beginDragging={(ev) => {
                      if (draggingNode() === null) {
                        setDragStartPos([ev.x, ev.y]);
                        setDraggingNode({ id: node.id, start: node.coords });
                      }
                    }}
                    onHoverIn={({ titlebar }) => {
                      setNodeHovered({ titlebar });
                    }}
                    onHoverOut={() => {
                      setNodeHovered(null);
                    }}
                  />
                );
              }}
            </For>
          </div>
        </div>
      </div>

      <div class="h-7 border-t flex flex-row items-center px-1 gap-3 text-theme-deemphasis text-sm">
        {(() => {
          const Hint: VoidComponent<{
            hide?: any | undefined | null | false;
            down: boolean;
            keys: VoidComponent<{ down: boolean }>;
            action: string;
          }> = (props) => {
            return (
              <Show when={!(props.hide ?? false)}>
                <div class="flex flex-row items-center gap-1 h-full">
                  <kbd class="flex flex-row gap-0.5 text-sm">
                    {props.keys({ down: props.down })}
                  </kbd>
                  <span>{props.action}</span>
                </div>
              </Show>
            );
          };

          const SnapConfigHints: VoidComponent<{
            hide: any | undefined | null | false;
            config: () => SnapConfig;
          }> = (props) => {
            const action = (kind: SnapKind): string =>
              Match.value(kind).pipe(
                Match.when("none", () => "disable snapping"),
                Match.whenOr("1s", "5s", (s) => `snap to ${s}`),
                Match.when(
                  "disabled",
                  () => "you shouldn't be able to see this",
                ),
                Match.exhaustive,
              );

            return (
              <>
                <Show when={!props.hide}>
                  <Hint
                    hide={props.config().shift === "disabled"}
                    down={shiftDown() && !ctrlDown()}
                    keys={(props) => <KeyboardKey.Shift down={props.down} />}
                    action={action(props.config().shift)}
                  />
                  <Hint
                    hide={props.config().ctrl === "disabled"}
                    down={ctrlDown() && !shiftDown()}
                    keys={(props) => <KeyboardKey.Ctrl down={props.down} />}
                    action={action(props.config().ctrl)}
                  />
                  <Hint
                    hide={props.config().ctrlShift === "disabled"}
                    down={shiftDown() && ctrlDown()}
                    keys={(props) => (
                      <>
                        <KeyboardKey.Shift down={props.down} /> +{" "}
                        <KeyboardKey.Ctrl down={props.down} />
                      </>
                    )}
                    action={action(props.config().ctrlShift)}
                  />
                </Show>
              </>
            );
          };

          return (
            <>
              <Hint
                hide={draggingNode() || dragZoom() || nodeHovered()}
                down={panning() !== null}
                keys={(props) => (
                  <>
                    <KeyboardKey.Space down={props.down} />+{" "}
                    <MouseButton kind="left" down={props.down} />
                    |
                    <MouseButton kind="middle" down={props.down} />
                  </>
                )}
                action="Pan view"
              />
              <SnapConfigHints hide={!panning()} config={panSnapConfig} />

              <Hint
                hide={panning() || draggingNode() || nodeHovered()}
                down={dragZoom()}
                keys={(props) => (
                  <>
                    <MouseButton kind="right" down={props.down} /> +{" "}
                    <MouseButton.Moving kind="vertical" />
                  </>
                )}
                action="Zoom"
              />

              <Hint
                hide={!nodeHovered()?.titlebar && !draggingNode()}
                down={leftMouseButtonDown()}
                keys={(props) => <MouseButton kind="left" down={props.down} />}
                action="Move"
              />
              <SnapConfigHints hide={!draggingNode()} config={nodeSnapConfig} />
            </>
          );
        })()}
      </div>
    </div>
  );
};

const RenderNode: VoidComponent<{
  node: Node;
  onTouch: () => void;
  snapNodeSizesToGrid: () => boolean;
  beginDragging: (ev: MouseEvent) => void;
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

  return (
    <div
      ref={setSizeRef}
      tabIndex="0"
      class="absolute border rounded-sm bg-theme-background/75 max-w-80 inline-flex flex-col box-border drop-shadow-xl -outline-offset-2 focus:outline-1 cursor-default"
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
        props.onTouch();
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

const GridStyle = ["grid_lines", "dot_matrix"] as const;
type GridStyle = (typeof GridStyle)[number];
const GridStyleNames: Record<GridStyle, string> = {
  grid_lines: "Lines",
  dot_matrix: "Dot matrix",
};

const RenderGrid: VoidComponent<{
  style?: JSX.CSSProperties;
  size: () => ElementSize;
  originOffset: () => Coords;
  zoom: () => number;
  gridStyle: () => GridStyle;
}> = (props) => {
  let canvasRef!: HTMLCanvasElement;

  const drawGrid: Record<
    GridStyle,
    (args: {
      ctx: CanvasRenderingContext2D;
      borderColor: string;
      size: ElementSize;
      originOffset: Coords;
      zoom: number;
    }) => void
  > = {
    grid_lines: ({ ctx, borderColor, size, originOffset: [ox, oy], zoom }) => {
      ctx.strokeStyle = borderColor;
      ctx.lineWidth = 1;

      const scaledGrid = GridSize * zoom;

      // verticals
      for (let kx = Math.ceil((0 - ox) / scaledGrid); ; kx++) {
        const x = Math.round(ox + kx * scaledGrid) + 0.5;
        if (x > size.width) break;
        const alpha = kx % 50 === 0 ? 0.8 : kx % 5 === 0 ? 0.5 : 0.2;
        ctx.globalAlpha = alpha;
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, size.height);
        ctx.stroke();
      }

      // horizontals
      for (let ky = Math.ceil((0 - oy) / scaledGrid); ; ky++) {
        const y = Math.round(oy + ky * scaledGrid) + 0.5;
        if (y > size.height) break;
        const alpha = ky % 50 === 0 ? 0.8 : ky % 5 === 0 ? 0.5 : 0.2;
        ctx.globalAlpha = alpha;
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(size.width, y);
        ctx.stroke();
      }
    },
    dot_matrix: ({ ctx, borderColor, size, originOffset: [ox, oy], zoom }) => {
      const r5s = 1;
      const a5s = 0.6;
      const r25s = 2;
      const a25s = 0.8;

      ctx.fillStyle = borderColor;

      const step = 5 * GridSize * zoom;

      const kxStart = Math.ceil((0 - ox) / step);
      const kxEnd = Math.floor((size.width - ox) / step);
      const kyStart = Math.ceil((0 - oy) / step);
      const kyEnd = Math.floor((size.height - oy) / step);

      for (let kx = kxStart; kx <= kxEnd; kx++) {
        const x = Math.round(ox + kx * step) + 0.5;

        for (let ky = kyStart; ky <= kyEnd; ky++) {
          const y = Math.round(oy + ky * step) + 0.5;

          const globalXUnits = kx * 5;
          const globalYUnits = ky * 5;

          if (globalXUnits % 25 === 0 && globalYUnits % 25 === 0) {
            ctx.globalAlpha = a25s;
            ctx.beginPath();
            ctx.arc(x, y, r25s, 0, Math.PI * 2);
            ctx.fill();
          } else {
            ctx.globalAlpha = a5s;
            ctx.beginPath();
            ctx.arc(x, y, r5s, 0, Math.PI * 2);
            ctx.fill();
          }
        }
      }
    },
  };

  createEffect(() => {
    const ctx = canvasRef.getContext("2d");
    if (!ctx) {
      console.error("no canvas context");
      return;
    }

    const size = props.size();
    const styles = getComputedStyle(canvasRef);

    const originOffset = props.originOffset();
    const borderColor = styles.getPropertyValue("--theme-border");

    const zoom = props.zoom();

    ctx.clearRect(0, 0, canvasRef.width, canvasRef.height);

    drawGrid[props.gridStyle()]({ ctx, borderColor, size, originOffset, zoom });
  });

  return (
    <canvas
      ref={canvasRef}
      class="absolute left-0 right-0 top-0 bottom-0 pointer-events-none"
      style={props.style}
      width={props.size().width}
      height={props.size().height}
    >
      {/**/}
    </canvas>
  );
};

const Settings: VoidComponent<{
  class?: string;
  snapNodeSizesToGrid: Accessor<boolean>;
  setSnapNodeSizesToGrid: Setter<boolean>;
  gridStyle: Accessor<GridStyle>;
  setGridStyle: Setter<GridStyle>;
  panSnapConfig: Accessor<SnapConfig>;
  setPanSnapConfig: Setter<SnapConfig>;
  nodeSnapConfig: Accessor<SnapConfig>;
  setNodeSnapConfig: Setter<SnapConfig>;
}> = (props) => {
  const SnapConfig: VoidComponent<{
    label: string;
    snapConfig: Accessor<SnapConfig>;
    setSnapConfig: Setter<SnapConfig>;
  }> = (props) => {
    const KindSelect: VoidComponent<{
      label: string;
      kind: () => SnapKind;
      setKind: (kind: SnapKind) => void;
    }> = (props) => {
      // intentional
      // eslint-disable-next-line solid/reactivity
      const initialDefault = props.kind();

      return (
        <Select<SnapKind>
          class="flex items-center gap-1 w-full"
          value={props.kind()}
          onChange={(s) => props.setKind(s ?? props.kind())}
          options={[...SnapKind]}
          defaultValue={initialDefault}
          itemComponent={(props) => (
            <Select.Item item={props.item}>{props.item.textValue}</Select.Item>
          )}
        >
          <Select.Label class="mr-auto">{props.label}</Select.Label>

          <Select.Trigger class="w-40">
            <Select.Value<GridStyle>>
              {(state) => state.selectedOption()}
            </Select.Value>
          </Select.Trigger>
          <Select.Content />
        </Select>
      );
    };

    return (
      <Collapsible>
        <Collapsible.Trigger class="div group flex flex-row gap-2 my-1">
          <Icon
            icon="ChevronRight"
            class="size-3 fill-none transition-transform duration-100 group-data-[expanded]:rotate-90"
          />
          <Label>{props.label}</Label>
        </Collapsible.Trigger>
        <Collapsible.Content class="mt-1 ml-8 flex flex-col gap-1">
          <KindSelect
            label="default"
            kind={() => props.snapConfig().default}
            setKind={(kind) =>
              props.setSnapConfig((c) => ({ ...c, default: kind }))
            }
          />
          <KindSelect
            label="shift"
            kind={() => props.snapConfig().shift}
            setKind={(kind) =>
              props.setSnapConfig((c) => ({ ...c, shift: kind }))
            }
          />
          <KindSelect
            label="ctrl"
            kind={() => props.snapConfig().ctrl}
            setKind={(kind) =>
              props.setSnapConfig((c) => ({ ...c, ctrl: kind }))
            }
          />
          <KindSelect
            label="ctrl+shift"
            kind={() => props.snapConfig().ctrlShift}
            setKind={(kind) =>
              props.setSnapConfig((c) => ({ ...c, ctrlShift: kind }))
            }
          />
        </Collapsible.Content>
      </Collapsible>
    );
  };

  return (
    <div class={cn("flex flex-col gap-1", props.class)}>
      <h2 class="text-lg underline underline-offset-2">Settings</h2>

      <Switch
        class="flex items-center gap-1 w-full"
        checked={props.snapNodeSizesToGrid()}
        onChange={() => props.setSnapNodeSizesToGrid((b) => !b)}
      >
        <Switch.Label class="mr-auto">Snap node sizes to grid</Switch.Label>

        <Switch.Control>
          <Switch.Thumb />
        </Switch.Control>
      </Switch>

      <Select<GridStyle>
        class="flex items-center gap-1 w-full"
        value={props.gridStyle()}
        onChange={(s) => props.setGridStyle(s ?? "grid_lines")}
        options={[...GridStyle]}
        defaultValue={"grid_lines"}
        itemComponent={(props) => (
          <Select.Item item={props.item}>
            {GridStyleNames[props.item.textValue]}
          </Select.Item>
        )}
      >
        <Select.Label class="mr-auto">Grid style</Select.Label>

        <Select.Trigger class="w-40">
          <Select.Value<GridStyle>>
            {(state) => GridStyleNames[state.selectedOption()]}
          </Select.Value>
        </Select.Trigger>
        <Select.Content />
      </Select>

      <SnapConfig
        label="Pan snap settings"
        snapConfig={props.panSnapConfig}
        setSnapConfig={props.setPanSnapConfig}
      />

      <SnapConfig
        label="Node snap settings"
        snapConfig={props.nodeSnapConfig}
        setSnapConfig={props.setNodeSnapConfig}
      />
    </div>
  );
};

export default NodeGraphTest;
