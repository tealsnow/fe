import {
  Index,
  VoidComponent,
  createSignal,
  onCleanup,
  onMount,
} from "solid-js";

import cn from "~/lib/cn";

import { draggable } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { createStore, produce } from "solid-js/store";

type ElementSize = {
  width: number;
  height: number;
};

export const createElementSize = <T extends HTMLElement>(): [
  () => ElementSize,
  (element: T) => void,
] => {
  const [size, setSize] = createSignal<ElementSize>({ width: 0, height: 0 });
  return [
    size,
    (element: T) => {
      new ResizeObserver(([entry]) => {
        const { width, height } = entry.contentRect;
        setSize({ width, height });
      }).observe(element);
    },
  ];
};

type Coords = [number, number];

type CanvasItem = {
  // id:
  coords: () => Coords;
  setCoords: (coords: Coords) => void;
  title: string;
  content: VoidComponent;
};
const CanvasItem = ({
  coords,
  title,
  content,
}: Omit<CanvasItem, "coords" | "setCoords"> & {
  coords: Coords;
}): CanvasItem => {
  const [getCoords, setCoords] = createSignal<Coords>(coords);
  return {
    coords: getCoords,
    setCoords,
    title,
    content,
  };
};

const CanvasTest: VoidComponent = () => {
  const [originOffset, setOriginOffset] = createSignal<Coords>([0, 0]);
  const [dragging, setDragging] = createSignal(false);

  const [canvasSize, setCanvasRef] = createElementSize();

  const [canvasItems, setCanvasItems] = createStore<CanvasItem[]>([
    CanvasItem({
      coords: [20, 30],
      title: "item 1",
      content: () => "some item 1 content",
    }),
    CanvasItem({
      coords: [100, 10],
      title: "item 2",
      content: () => "some item 2 content",
    }),
  ]);

  return (
    <div ref={setCanvasRef} class="size-full flex flex-col">
      <div class="h-6 border-b flex flex-row items-center px-1 gap-4">
        <pre>
          offset: [{originOffset()[0]}, {originOffset()[1]}]
        </pre>
        <pre>
          size: [{canvasSize().width}, {canvasSize().height}]
        </pre>
      </div>
      <div class="size-full relative overflow-hidden">
        <div
          class={cn(
            "size-full",
            dragging() ? "cursor-grabbing" : "cursor-grab",
          )}
          onMouseDown={(ev) => {
            ev.preventDefault();
            setDragging(true);
          }}
          onMouseMove={(ev) => {
            if (!dragging()) return;
            ev.preventDefault();

            const [x, y] = originOffset();
            setOriginOffset([x + ev.movementX, y + ev.movementY]);
          }}
          onMouseUp={() => {
            setDragging(false);
          }}
          onMouseLeave={() => {
            setDragging(false);
          }}
        />

        <div
          class="absolute size-0 overflow-visible"
          style={{
            left: `${originOffset()[0]}px`,
            top: `${originOffset()[1]}px`,
          }}
        >
          <Index each={canvasItems}>
            {(item, idx) => (
              <RenderCanvasItem
                item={item}
                onTouch={() =>
                  // move the touched item last so it will render on top
                  setCanvasItems(
                    produce((items) => items.push(items.splice(idx, 1)[0])),
                  )
                }
              />
            )}
          </Index>
        </div>
      </div>
    </div>
  );
};

const RenderCanvasItem: VoidComponent<{
  item: () => CanvasItem;
  onTouch: () => void;
}> = (props) => {
  let titleRef!: HTMLDivElement;
  onMount(() => {
    const cleanup = draggable({
      element: titleRef,

      onGenerateDragPreview: ({ nativeSetDragImage }) => {
        disableNativeDragPreview({ nativeSetDragImage });
      },

      getInitialData: () => {
        const [x, y] = props.item().coords();
        return { x, y };
      },
      onDrag: ({ location, source }) => {
        const deltaX =
          location.current.input.clientX - location.initial.input.clientX;
        const deltaY =
          location.current.input.clientY - location.initial.input.clientY;

        const x = source.data.x as number;
        const y = source.data.y as number;
        props.item().setCoords([x + deltaX, y + deltaY]);
      },
    });
    onCleanup(() => cleanup());
  });

  return (
    <div
      class="absolute border rounded-sm bg-theme-background"
      style={{
        left: `${props.item().coords()[0]}px`,
        top: `${props.item().coords()[1]}px`,
      }}
      onMouseDown={() => {
        props.onTouch();
      }}
    >
      <div
        ref={titleRef}
        class="border-b whitespace-nowrap px-1 py-0.5 bg-theme-panel-tab-background-active cursor-grab"
      >
        {props.item().title}
      </div>
      <div class="p-1">{props.item().content({})}</div>
    </div>
  );
};

export default CanvasTest;
