import {
  createSignal,
  createEffect,
  ParentProps,
  onMount,
  createContext,
  useContext,
  onCleanup,
} from "solid-js";
import * as uuid from "uuid";
import { css } from "solid-styled-components";

import * as ef from "effect";

import { DragLocationHistory } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";
import { draggable } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";

import { cn } from "~/lib/cn";

export type StringPropertyProps = {
  key: string;
  value: string;
  format?: (value: string) => string;
  onUpdate?: (newValue: string) => void;
  onClick?: () => void;
};

export const StringProperty = (props: StringPropertyProps) => {
  const formattedValue = () =>
    props.format ? props.format(props.value) : props.value;

  const [editing, setEditing] = createSignal(false);
  const [editValue, setEditValue] = createSignal(props.value);

  let inputRef!: HTMLInputElement;
  createEffect(() => {
    if (editing()) {
      inputRef.focus();
      inputRef.select();
    } else {
      setEditValue(props.value);
    }
  });

  const interactive = () => props.onClick || props.onUpdate;

  const context = useContext(PropertyEditorContext)!;

  return (
    <div // table row
      class="flex flex-row w-full not-last:border-b border-theme-border items-center"
    >
      <div // table cell: key
        class="px-1 overflow-clip"
        style={{
          width: `calc(var(${context.resizeWidthCssVar}, var(--col-width)) * 1px)`,
        }}
      >
        {props.key}
      </div>

      <div // table cell: value
        class="grow"
      >
        <input
          ref={inputRef}
          class={cn(
            "ring-0 min-h-0 min-w-0 h-full w-full p-0 px-1 box-border bg-theme-background border border-theme-colors-blue-border",
            interactive() && "bg-theme-colors-blue-background",
            editing() &&
              "border-theme-colors-purple-border bg-theme-colors-purple-background",
            props.onClick &&
              !props.onUpdate &&
              "cursor-pointer transition-colors hover:bg-theme-colors-blue-base",
          )}
          size={1} // required for min-w to work
          type="text"
          readOnly={!editing()}
          name={props.key}
          value={editing() ? editValue() : formattedValue()}
          onClick={props.onClick}
          onDblClick={() => (props.onUpdate ? setEditing(true) : void {})}
          onBlur={() => setTimeout(() => setEditing(false), 100)}
          onInput={({ currentTarget: { value } }) => setEditValue(value)}
          onKeyDown={({ key }) => {
            switch (key) {
              case "Enter":
                if (props.onUpdate) props.onUpdate(editValue());
                setEditing(false);
                break;
              case "Escape":
                setEditing(false);
                break;
            }
          }}
        >
          {props.value}
        </input>
      </div>
    </div>
  );
};

export type PropertyEditorProps = ParentProps<{}>;

export const PropertyEditor = (props: PropertyEditorProps) => {
  let tableRef!: HTMLDivElement;

  const [width, setWidth] = createSignal(0.5);
  const [widthPx, setWidthPx] = createSignal<number>(0);
  const updateWidthPx = () => setWidthPx(width() * tableRef.clientWidth);
  createEffect(() => updateWidthPx(), [width]);

  const [resizing, setResizing] = createSignal(false);

  onMount(() => {
    const observer = new ResizeObserver(() => {
      updateWidthPx();
    });

    observer.observe(tableRef);

    onCleanup(() => {
      observer.disconnect();
    });
  });

  const resizeWidthCssVar = `--local-resize-width-${uuid.v4()}`;
  let headerResizeHandleRef!: HTMLDivElement;

  onMount(() => {
    const getResizeWidth = (location: DragLocationHistory): number => {
      const delta =
        location.current.input.clientX - location.initial.input.clientX;

      return ef.Order.clamp(ef.Order.number)({
        minimum: 0,
        maximum: tableRef.clientWidth,
      })(widthPx() + delta);
    };

    const dragCleanup = draggable({
      element: headerResizeHandleRef,

      onGenerateDragPreview: ({ nativeSetDragImage }) => {
        disableNativeDragPreview({ nativeSetDragImage });
        preventUnhandled.start();
      },

      onDrag: ({ location }) => {
        const resizeWidth = getResizeWidth(location);

        tableRef.style.setProperty(resizeWidthCssVar, `${resizeWidth}`);

        setResizing(true);
      },

      onDrop: ({ location }) => {
        preventUnhandled.stop();

        const resizeWidth = getResizeWidth(location);
        setWidth(resizeWidth / tableRef.clientWidth);
        tableRef.style.removeProperty(resizeWidthCssVar);

        setResizing(false);
      },
    });

    onCleanup(() => {
      dragCleanup();
    });
  });

  return (
    <PropertyEditorContext.Provider
      value={{
        resizeWidthCssVar,
      }}
    >
      <div // table
        ref={tableRef}
        class="w-full border-2 border-theme-border min-w-0 text-nowrap"
        style={{
          "--col-width": widthPx(),
        }}
      >
        <div // table head
          class="w-full border-b-2 border-theme-border text-bold"
        >
          <div // table row
            class="w-full flex flex-row"
          >
            <div // table cell
              class="p-1 overflow-hidden"
              style={{
                width: `calc(var(${resizeWidthCssVar}, var(--col-width)) * 1px)`,
              }}
            >
              Key
            </div>

            <div // resize handle
              ref={headerResizeHandleRef}
              class={cn(
                "relative w-0.5 cursor-col-resize",
                "transition-color bg-theme-border hover:bg-theme-text",
                resizing() && "bg-theme-text",
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
              onDblClick={() => setWidth(0.5)}
            />

            <div // table cell
              class="p-1 min-w-0"
            >
              Value
            </div>
          </div>
        </div>
        <div // table body
        >
          {props.children}
        </div>
      </div>
    </PropertyEditorContext.Provider>
  );
};

type PropertyEditorContext = {
  resizeWidthCssVar: string;
};

const PropertyEditorContext = createContext<PropertyEditorContext>();
