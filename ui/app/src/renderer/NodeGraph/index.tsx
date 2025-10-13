import { For, Show, VoidComponent, createSignal, batch } from "solid-js";
import { createStore, produce } from "solid-js/store";
import { makePersisted } from "@solid-primitives/storage";
import { DocumentEventListener } from "@solid-primitives/event-listener";
import { MapOption } from "solid-effect";

import { Data, Match, Option, Order } from "effect";

import cn from "~/lib/cn";
import UUID from "~/lib/UUID";
import { createElementSize, ElementSize } from "~/lib/createElementSize";
import taggedEnumAs from "~/lib/taggedEnumAs";

import Icon from "~/ui/components/Icon";
import Button from "~/ui/components/Button";
import KeyboardKey from "~/ui/components/KeyboardKey";
import MouseButton from "~/ui/components/MouseButton";

import {
  Config,
  ConfigDefault,
  SnapKind,
  SnapConfig,
  ZoomMinMax,
} from "./Config";
import Settings from "./Settings";
import {
  Coords,
  coordsSnapToGrid,
  snapKindToNumber,
  snapKindForConfig,
} from "./coords";
import { Node, RenderNode } from "./Node";
import { RenderGrid } from "./RenderGrid";

import { InputContextProvider, useInputContext } from "./InputContextProvider";

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

type DraggingStateMode = Data.TaggedEnum<{
  node: {
    nodes: {
      start: Coords;
      id: UUID;
    }[];
  };
  canvas: {
    start: Coords;
  };
  zoom: {};
  selection: {
    start: Coords;
    end: Coords;
  };
}>;
const DraggingStateMode = Data.taggedEnum<DraggingStateMode>();

type DraggingState = {
  startPos: Coords;
  mode: DraggingStateMode;
};

type CanvasState = {
  offset: Coords;
  zoom: number;
  mouseInside: boolean;
  sidebarOpen: boolean;
  nodeHovered: null | {
    titlebar: boolean;
  };
};

const NodeGraph: VoidComponent<{}> = () => {
  return (
    <InputContextProvider>
      <NodeGraphInner />
    </InputContextProvider>
  );
};

const NodeGraphInner: VoidComponent<{}> = () => {
  const [config, setConfig] = makePersisted(
    // doesn't understand what makePersisted is
    // eslint-disable-next-line solid/reactivity
    createStore<Config>(ConfigDefault),
    {
      name: "nodeGraph-config",
      storage: localStorage,
    },
  );

  const [draggingState, setDraggingState] = createSignal<DraggingState | null>(
    null,
  );

  const [canvas, setCanvas] = createStore<CanvasState>({
    offset: [10, 10],
    zoom: 1,
    mouseInside: false,
    sidebarOpen: true,
    nodeHovered: null,
  });

  const inputContext = useInputContext();

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
    Node({
      title: "test 1",
      color: "green",
      content: () => "some content",
      coords: [320, 220],
    }),
    Node({
      title: "test 2",
      color: "green",
      content: () => "some content",
      coords: [420, 220],
    }),
  ]);

  const [nodeSizes, setNodeSizes] = createStore<Record<UUID, ElementSize>>({});

  const [selectedNodes, setSelectedNodes] = createStore<UUID[]>([]);

  const [containerSize, setContainerSizeRef] = createElementSize();
  let containerRef!: HTMLDivElement;

  const handleZoom = (delta: number, [x, y]: Coords): void => {
    const oldZoom = canvas.zoom;

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
    const [ox, oy] = canvas.offset;
    const worldX = (mouseX - ox) / oldZoom;
    const worldY = (mouseY - oy) / oldZoom;

    // new origin so mouse stays fixed in same world space
    const newX = mouseX - worldX * newZoom;
    const newY = mouseY - worldY * newZoom;

    setCanvas((s) => ({
      ...s,
      offset: [newX, newY],
      zoom: newZoom,
    }));
  };

  const onWheel = (ev: WheelEvent): void => {
    ev.preventDefault();

    if (ev.ctrlKey) {
      handleZoom(ev.deltaY * -8, [ev.clientX, ev.clientY]);
    } else {
      const speed = 0.2;
      const [ox, oy] = canvas.offset;
      const dx = ev.deltaX * speed;
      const dy = ev.deltaY * speed;

      if (ev.shiftKey) {
        setCanvas("offset", [ox - dy, oy]);
      } else {
        setCanvas("offset", [ox - dx, oy - dy]);
      }
    }
  };

  const onMouseDown = (ev: MouseEvent): void => {
    if (draggingState() !== null) return;
    ev.preventDefault();

    const leftButton = 0;
    const middleButton = 1;
    const rightButton = 2;

    if (ev.button === rightButton) {
      setDraggingState({
        startPos: [ev.x, ev.y],
        mode: DraggingStateMode.zoom(),
      });
    } else if (
      (inputContext.space && ev.button === leftButton) ||
      ev.button === middleButton
    ) {
      setDraggingState({
        startPos: [ev.x, ev.y],
        mode: DraggingStateMode.canvas({ start: canvas.offset }),
      });
    } else if (ev.button === leftButton) {
      batch(() => {
        setSelectedNodes([]);
        containerRef.focus();

        const coords: Coords = [ev.x, ev.y];
        setDraggingState({
          startPos: coords,
          mode: DraggingStateMode.selection({
            start: coords,
            end: coords,
          }),
        });
      });
    }
  };

  const onMouseMove = (ev: MouseEvent): void => {
    setCanvas("mouseInside", true);

    const dragging = draggingState();
    if (!dragging) return;

    const [startX, startY] = dragging.startPos;

    DraggingStateMode.$match({
      node: ({ nodes }) => {
        batch(() => {
          for (const node of nodes) {
            const [x, y] = node.start;
            const id = node.id;

            // delta from where the drag started,
            // adjusted to the zoom factor
            const dx = (ev.x - startX) / canvas.zoom;
            const dy = (ev.y - startY) / canvas.zoom;

            const newCoords: Coords = [x + dx, y + dy];

            const snapped = coordsSnapToGrid(
              newCoords,
              snapKindToNumber(
                snapKindForConfig(config.snapping.nodes, {
                  ctrl: ev.ctrlKey,
                  shift: ev.shiftKey,
                }),
              ),
            );

            setNodes(
              (node) => node.id == id,
              (node) => ({
                ...node,
                coords: snapped,
              }),
            );
          }
        });
      },
      canvas: ({ start: [x, y] }) => {
        containerRef.focus();

        // delta from where the drag started
        const dx = ev.x - startX;
        const dy = ev.y - startY;

        const [ox, oy] = [x + dx, y + dy];

        // convert offset from screen -> world -> snap -> back to screen
        const zoom = canvas.zoom;
        const worldOffset: Coords = [ox / zoom, oy / zoom];
        const snappedWorldOffset = coordsSnapToGrid(
          worldOffset,
          snapKindToNumber(
            snapKindForConfig(config.snapping.canvas, {
              ctrl: ev.ctrlKey,
              shift: ev.shiftKey,
            }),
          ),
        );
        const newOffset: Coords = [
          snappedWorldOffset[0] * zoom,
          snappedWorldOffset[1] * zoom,
        ];

        setCanvas("offset", newOffset);
      },
      zoom: () => {
        containerRef.focus();

        const dy = ev.y - startY;

        const rect = containerRef.getBoundingClientRect();
        const centerX = rect.width / 2;
        const centerY = rect.height / 2;

        handleZoom(
          dy * -0.25,
          ev.ctrlKey ? [centerX, centerY] : [startX, startY],
        );
      },
      selection: (selection) => {
        const end: Coords = [ev.x, ev.y];
        setDraggingState({
          startPos: [startX, startY],
          mode: DraggingStateMode.selection({
            start: selection.start,
            end,
          }),
        });

        const updateSelection = async (): Promise<void> => {
          const inSelection: UUID[] = [];

          for (const node of nodes) {
            const size = nodeSizes[node.id];
            if (!size) continue;

            const rect = containerRef.getBoundingClientRect();

            // convert node coords to screen space
            const normalizedLeftX =
              node.coords[0] + canvas.offset[0] / canvas.zoom;
            const normalizedTopY =
              node.coords[1] + canvas.offset[1] / canvas.zoom;

            const normalizedRightX =
              node.coords[0] + size.width + canvas.offset[0] / canvas.zoom;
            const normalizedBottomY =
              node.coords[1] + size.height + canvas.offset[1] / canvas.zoom;

            // get selection start and end in screen coords
            const selectionStartX =
              (selection.start[0] - rect.left) / canvas.zoom;
            const selectionStartY =
              (selection.start[1] - rect.top) / canvas.zoom;

            const selectionEndX = (selection.end[0] - rect.left) / canvas.zoom;
            const selectionEndY = (selection.end[1] - rect.top) / canvas.zoom;

            // get selection start and end normalized regardless of
            // start and end direction
            const normalizedSelectionStartX =
              selectionStartX < selectionEndX ? selectionStartX : selectionEndX;
            const normalizedSelectionEndX =
              selectionEndX < selectionStartX ? selectionStartX : selectionEndX;

            const normalizedSelectionStartY =
              selectionStartY < selectionEndY ? selectionStartY : selectionEndY;
            const normalizedSelectionEndY =
              selectionEndY < selectionStartY ? selectionStartY : selectionEndY;

            // check each edge
            const inLeftX =
              normalizedLeftX > normalizedSelectionStartX &&
              normalizedLeftX < normalizedSelectionEndX;

            const inTopY =
              normalizedTopY > normalizedSelectionStartY &&
              normalizedTopY < normalizedSelectionEndY;

            const inRightX =
              normalizedRightX > normalizedSelectionStartX &&
              normalizedRightX < normalizedSelectionEndX;

            const inBottomY =
              normalizedBottomY > normalizedSelectionStartY &&
              normalizedBottomY < normalizedSelectionEndY;

            // check each corner
            const inTopLeft = inLeftX && inTopY;
            const inTopRight = inRightX && inTopY;
            const inBottomLeft = inLeftX && inBottomY;
            const inBottomRight = inRightX && inBottomY;

            // maybe we could select if any part is inside the selection
            // but not sure how to do that without a lot of extra work

            // const select =
            //   inTopLeft || inTopRight || inBottomLeft || inBottomRight;
            // const select =
            //   inTopLeft && inTopRight && inBottomLeft && inBottomRight;
            const select =
              (inTopLeft && inTopRight) ||
              (inTopRight && inBottomRight) ||
              (inBottomRight && inBottomLeft) ||
              (inBottomLeft && inTopLeft);

            if (select) inSelection.push(node.id);
          }

          setSelectedNodes(inSelection);
        };

        updateSelection();
      },
    })(dragging.mode);
  };

  return (
    <div class="size-full flex flex-col">
      <DocumentEventListener
        onKeydown={(ev) => {
          if (ev.key === " ") {
            if (canvas.mouseInside && !containerRef.matches(":focus-within"))
              containerRef.focus();
          }
        }}
      />

      <div class="h-7 border-b flex flex-row items-center px-1 gap-4 overflow-y-scroll no-scrollbar">
        <Button
          as={Icon}
          icon={
            canvas.sidebarOpen
              ? "SidebarIndicatorEnabled"
              : "SidebarIndicatorDisabled"
          }
          variant="icon"
          size="icon"
          class="ml-auto rotate-270"
          highlighted={canvas.sidebarOpen}
          onClick={() => setCanvas("sidebarOpen", (b) => !b)}
        />
      </div>

      <div class="flex flex-row-reverse size-full">
        <Show when={canvas.sidebarOpen}>
          <div class="min-w-1/3 max-w-1/3 border-l flex flex-col [&>div]:p-2">
            <Settings
              class="h-2/3 border-b"
              config={config}
              setConfig={setConfig}
            />
            <div class="h-1/3 flex flex-col overflow-x-scroll">
              <h2 class="text-lg underline underline-offset-2">Dbg</h2>

              <div class="flex flex-row items-center gap-2">
                <pre>
                  offset: [{canvas.offset[0].toFixed(2)},{" "}
                  {canvas.offset[1].toFixed(2)}]
                </pre>
                <Button
                  size="small"
                  variant="outline"
                  onClick={() => setCanvas("offset", [0, 0])}
                >
                  reset
                </Button>
              </div>
              <pre>
                size: [{containerSize().width.toFixed(2)},{" "}
                {containerSize().height.toFixed(2)}]
              </pre>
              <div class="flex flex-row items-center gap-2">
                <pre>zoom: {canvas.zoom.toFixed(2)}</pre>
                <Button
                  size="small"
                  variant="outline"
                  onClick={() => setCanvas("zoom", 1)}
                >
                  reset
                </Button>
              </div>

              <pre>nodeHovered: {JSON.stringify(canvas.nodeHovered)}</pre>

              <pre>
                Selected Nodes: [
                <For each={selectedNodes}>
                  {(id, idx) => {
                    const name = nodes.find((node) => node.id === id)!.title;
                    const [x, y] = nodes.find((node) => node.id === id)!.coords;
                    const { width, height } = nodeSizes[id];

                    return (
                      <>
                        <Show when={idx() === 0}>
                          <br />
                        </Show>
                        {"    "}"{name}" -- {id}
                        <br />
                        {"    "}
                        {"    "}
                        coords: [{x.toFixed(2)}, {y.toFixed(2)}]
                        <br />
                        {"    "}
                        {"    "}
                        size: [{width.toFixed(2)}, {height.toFixed(2)}]
                        <br />
                      </>
                    );
                  }}
                </For>
                ]
              </pre>
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
            inputContext.space && "cursor-grab",
            Option.fromNullable(draggingState()).pipe(
              Option.map((dragging) =>
                DraggingStateMode.$match({
                  canvas: () => "cursor-grabbing",
                  node: () => "cursor-move",
                  zoom: () => "cursor-ns-resize",
                  selection: () => "",
                })(dragging.mode),
              ),
              Option.getOrUndefined,
            ),
          )}
          onWheel={onWheel}
          onMouseDown={onMouseDown}
          onMouseMove={onMouseMove}
          onMouseUp={() => {
            setDraggingState(null);
          }}
          onMouseEnter={() => {
            setCanvas("mouseInside", true);
          }}
          onMouseLeave={() => {
            batch(() => {
              setCanvas("mouseInside", false);

              setDraggingState(null);
            });
          }}
        >
          <RenderGrid
            size={containerSize}
            offset={() => canvas.offset}
            gridStyle={() => config.gridStyle}
            zoom={() => canvas.zoom}
          />

          <MapOption
            on={taggedEnumAs<DraggingStateMode, "selection">("selection")(
              draggingState()?.mode,
            )}
          >
            {(selection) => {
              const rect = containerRef.getBoundingClientRect();

              const start = (): Coords => draggingState()!.startPos;

              const coords = (): {
                x: number;
                y: number;
                width: number;
                height: number;
              } => {
                const [startX, startY] = start();
                const [endX, endY] = selection().end;

                const [x, width] =
                  startX < endX
                    ? [startX - rect.left, endX - startX]
                    : [endX - rect.left, startX - endX];
                const [y, height] =
                  startY < endY
                    ? [startY - rect.top, endY - startY]
                    : [endY - rect.top, startY - endY];

                return { x, y, width, height };
              };

              return (
                <div
                  class="absolute z-20 bg-theme-colors-aqua-background/20 border-theme-colors-aqua-border border-2"
                  style={{
                    transform: `
                      translate(
                        ${coords().x}px,
                        ${coords().y}px
                      )
                    `,
                    width: `${coords().width}px`,
                    height: `${coords().height}px`,
                  }}
                />
              );
            }}
          </MapOption>

          <Show when={DraggingStateMode.$is("zoom")(draggingState()?.mode)}>
            {(() => {
              const rect = containerRef.getBoundingClientRect();
              return (
                <svg
                  class="absolute"
                  style={{
                    transform: `translate(
                      ${draggingState()!.startPos[0] - rect.left - 8}px,
                      ${draggingState()!.startPos[1] - rect.top - 8}px
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
                  ${canvas.offset[0]}px,
                  ${canvas.offset[1]}px
                )
                scale(${canvas.zoom})
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
                    selected={() => selectedNodes.includes(node.id)}
                    snapNodeSizesToGrid={() => config.snapNodeSizesToGrid}
                    beginDragging={(ev) =>
                      batch(() => {
                        if (draggingState()) return;

                        if (
                          selectedNodes.length > 0 &&
                          selectedNodes.includes(node.id)
                        ) {
                          setDraggingState({
                            startPos: [ev.x, ev.y],
                            mode: DraggingStateMode.node({
                              nodes: selectedNodes.map((id) => ({
                                id,
                                start: nodes.find((node) => node.id === id)!
                                  .coords,
                              })),
                            }),
                          });
                        } else {
                          setSelectedNodes([node.id]);
                          setDraggingState({
                            startPos: [ev.x, ev.y],
                            mode: DraggingStateMode.node({
                              nodes: [
                                {
                                  id: node.id,
                                  start: node.coords,
                                },
                              ],
                            }),
                          });
                        }
                      })
                    }
                    sized={(size) => {
                      setNodeSizes((sizes) => ({
                        ...sizes,
                        [node.id]: size,
                      }));
                    }}
                    onMouseDown={(ev) =>
                      batch(() => {
                        // move the touched item last so it will render on top
                        setNodes(
                          produce((items) =>
                            items.push(items.splice(idx(), 1)[0]),
                          ),
                        );

                        if (draggingState() !== null) return;

                        if (ev.ctrlKey) {
                          setSelectedNodes((nodes) => [...nodes, node.id]);
                        } else {
                          setSelectedNodes([node.id]);
                        }
                      })
                    }
                    onHoverIn={({ titlebar }) => {
                      setCanvas("nodeHovered", { titlebar });
                    }}
                    onHoverOut={() => {
                      setCanvas("nodeHovered", null);
                    }}
                  />
                );
              }}
            </For>
          </div>
        </div>
      </div>

      <InputHints
        config={config}
        canvas={canvas}
        draggingState={draggingState}
      />
    </div>
  );
};

export default NodeGraph;

const InputHints: VoidComponent<{
  config: Config;
  canvas: CanvasState;
  draggingState: () => DraggingState | null;
}> = (props) => {
  const inputContext = useInputContext();

  return (
    <div class="h-7 border-t flex flex-row items-center px-1 gap-3 text-theme-deemphasis text-sm">
      {(() => {
        const Hint: VoidComponent<
          {
            down: boolean;
            keys: VoidComponent<{ down: boolean }>;
            action: string;
          } & (
            | {
                hide?: any | undefined | null | false;
                show?: never;
              }
            | {
                hide?: never;
                show?: any | undefined | null | false;
              }
          )
        > = (props) => {
          const show = (): boolean =>
            (props.show ?? false) || !(props.hide ?? false);
          return (
            <Show when={show()}>
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
              Match.when("disabled", () => "you shouldn't be able to see this"),
              Match.exhaustive,
            );

          return (
            <>
              <Show when={!props.hide}>
                <Hint
                  hide={props.config().shift === "disabled"}
                  down={inputContext.shift && !inputContext.ctrl}
                  keys={(props) => <KeyboardKey.Shift down={props.down} />}
                  action={action(props.config().shift)}
                />
                <Hint
                  hide={props.config().ctrl === "disabled"}
                  down={inputContext.ctrl && !inputContext.shift}
                  keys={(props) => <KeyboardKey.Ctrl down={props.down} />}
                  action={action(props.config().ctrl)}
                />
                <Hint
                  hide={props.config().ctrlShift === "disabled"}
                  down={inputContext.shift && inputContext.ctrl}
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
              hide={
                props.canvas.nodeHovered !== null ||
                (props.draggingState() !== null
                  ? !DraggingStateMode.$is("canvas")(
                      props.draggingState()?.mode,
                    )
                  : false)
              }
              down={DraggingStateMode.$is("canvas")(
                props.draggingState()?.mode,
              )}
              keys={(props) => (
                <>
                  <KeyboardKey.Space down={props.down} /> +{" "}
                  <MouseButton kind="left" down={props.down} />
                  |
                  <MouseButton kind="middle" down={props.down} />
                </>
              )}
              action="Pan"
            />
            <SnapConfigHints
              hide={
                !DraggingStateMode.$is("canvas")(props.draggingState()?.mode)
              }
              config={() => props.config.snapping.canvas}
            />

            <Hint
              hide={
                props.canvas.nodeHovered !== null ||
                (props.draggingState() !== null
                  ? !DraggingStateMode.$is("zoom")(props.draggingState()?.mode)
                  : false)
              }
              down={DraggingStateMode.$is("zoom")(props.draggingState()?.mode)}
              keys={(props) => (
                <>
                  <MouseButton kind="right" down={props.down} /> +{" "}
                  <MouseButton.Moving kind="vertical" />
                </>
              )}
              action="Zoom"
            />
            <Hint
              hide={
                props.canvas.nodeHovered !== null ||
                (props.draggingState() !== null
                  ? !DraggingStateMode.$is("selection")(
                      props.draggingState()?.mode,
                    )
                  : false)
              }
              down={DraggingStateMode.$is("selection")(
                props.draggingState()?.mode,
              )}
              keys={(props) => (
                <>
                  <MouseButton kind="left" down={props.down} />
                </>
              )}
              action="Select"
            />

            <Hint
              hide={
                (!props.canvas.nodeHovered?.titlebar &&
                  !DraggingStateMode.$is("node")(
                    props.draggingState()?.mode,
                  )) ||
                DraggingStateMode.$is("selection")(props.draggingState()?.mode)
              }
              down={inputContext.leftMouseButton}
              keys={(props) => <MouseButton kind="left" down={props.down} />}
              action="Move"
            />
            <SnapConfigHints
              hide={!DraggingStateMode.$is("node")(props.draggingState()?.mode)}
              config={() => props.config.snapping.nodes}
            />
          </>
        );
      })()}
    </div>
  );
};
