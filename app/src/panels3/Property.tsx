import {
  createSignal,
  createEffect,
  ParentProps,
  onMount,
  createContext,
  useContext,
  onCleanup,
  For,
  JSX,
  mergeProps,
  Show,
} from "solid-js";
import { makePersisted } from "@solid-primitives/storage";
import * as uuid from "uuid";
import { css } from "solid-styled-components";

import { Order } from "effect";

import { DragLocationHistory } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";
import { draggable } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";

import { cn } from "~/lib/cn";
import { Icon } from "~/assets/icons";

const Row = (props: JSX.HTMLAttributes<HTMLDivElement>) => {
  return (
    <div
      {...props}
      class={cn(
        "flex flex-row w-full h-6 border-b border-theme-border items-center",
        props.class,
      )}
    >
      {props.children}
    </div>
  );
};

type KeyProps = JSX.HTMLAttributes<HTMLDivElement> & {
  noPadding?: boolean;
};

const KeyProps = {
  noPadding: false,
};

const Key = (inProps: KeyProps) => {
  const props = mergeProps(KeyProps, inProps);

  const context = useContext(PropertyEditorContext)!;

  return (
    <div
      {...props}
      class={cn(
        "px-1 pt-1 pb-0.5 overflow-clip h-6",
        context.hasArray() && "ml-4", // to be kept in sync with style.width
        props.class,
      )}
      style={{
        width:
          context.hasArray() && !props.noPadding
            ? `calc(var(${context.resizeWidthCssVar}, var(--col-width)) * 1px - calc(var(--spacing) * 4))` // to be kept in sync with style.ml
            : `calc(var(${context.resizeWidthCssVar}, var(--col-width)) * 1px)`,
      }}
    >
      {props.children}
    </div>
  );
};

const Value = (props: JSX.HTMLAttributes<HTMLDivElement>) => {
  return (
    <div
      {...props}
      class={cn(
        "border-l-2 pb-[1px] h-6 border-theme-border grow",
        props.class,
      )}
    >
      {props.children}
    </div>
  );
};

export type StringPropertyProps = {
  key: string;
  value: string;
  format?: (value: string) => string;
  onUpdate?: (newValue: string) => void;
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

  return (
    <Row>
      <Key>{props.key}</Key>

      <Value>
        <input
          ref={inputRef}
          type="text"
          class={cn(
            "ring-0 min-h-0 min-w-0 h-full w-full p-0 px-1 pt-0.5 box-border bg-theme-background border border-theme-colors-blue-border text-sm/tight",
            props.onUpdate && "bg-theme-colors-blue-background",
            editing() &&
              "border-theme-colors-purple-border bg-theme-colors-purple-background",
          )}
          size={1} // required for min-w to work
          title="Double click to edit" // TODO: a more app level tooltip might be nicer here
          readOnly={!editing()}
          name={props.key}
          value={editing() ? editValue() : formattedValue()}
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
      </Value>
    </Row>
  );
};

export type ButtonPropertyProps = ParentProps<{
  key: string;
  onClick?: () => void;
}>;

export const ButtonProperty = (props: ButtonPropertyProps) => {
  return (
    <Row>
      <Key>{props.key}</Key>

      <Value>
        <button
          class={cn(
            "min-h-0 min-w-0 h-full w-full px-1 pt-0.5 box-border border border-theme-colors-aqua-border text-left text-sm/tight",
            props.onClick &&
              "cursor-pointer bg-theme-colors-aqua-background transition-colors hover:bg-theme-colors-aqua-base",
          )}
          onClick={props.onClick}
        >
          {props.children}
        </button>
      </Value>
    </Row>
  );
};

export type EnumPropertyProps<T> = {
  key: string;
  value: T;
  options: T[];
  onChange: (value: T) => void;
  render?: (value: T) => JSX.Element;
};

export const EnumPropertyProps = {
  render: (value: any) => <>{value}</>,
};

export const EnumProperty = <T,>(inProps: EnumPropertyProps<T>) => {
  const props = mergeProps(EnumPropertyProps, inProps);

  return (
    <Row>
      <Key>{props.key}</Key>

      <Value class="flex gap-[1px]">
        <For each={props.options}>
          {(option) => (
            <button
              class={cn(
                "grow h-full px-1 pt-0.5 border border-theme-colors-green-border transition-colors hover:bg-theme-colors-green-base cursor-pointer items-center text-center text-sm/tight",
                props.value === option && "bg-theme-colors-green-base",
              )}
              onClick={() => {
                props.onChange(option);
              }}
            >
              {props.render(option as any)}
            </button>
          )}
        </For>
      </Value>
    </Row>
  );
};

export type ArrayPropertyProps<T> = {
  key: string;
  items: T[];
  previewCount?: number;
  render: (item: T) => JSX.Element;
  preview?: (item: T) => JSX.Element;
};

export const ArrayProperty = <T,>(props: ArrayPropertyProps<T>) => {
  const preview = props.preview || props.render;
  const previewCount = props.previewCount ?? 3;

  const context = useContext(PropertyEditorContext)!;
  context.setHasArray(true);

  const [expanded, setExpanded] = makePersisted(createSignal(false), {
    storage: sessionStorage,
    name: `array-property-${props.key}-expanded`,
  });
  createEffect(() => {
    context.setAnyArrayExpanded(expanded());
  });

  return (
    <>
      <Row class="flex-col">
        <Row class={cn(expanded() && "last:border-b-1 h-7")}>
          <Key class="flex items-center gap-1 ml-0 pt-0" noPadding>
            <button
              class={cn(
                "w-3 h-4 self-center cursor-pointer transition-transform duration-100",
                expanded() && "rotate-90",
              )}
              onClick={() => setExpanded(!expanded())}
            >
              <Icon kind="chevron_right" class="fill-transparent size-3 p-0" />
            </button>
            <div class="pt-0.5">{props.key}</div>
          </Key>

          <Value class="h-full overflow-clip flex items-center">
            [
            {[
              props.items.slice(0, previewCount).map((item, index) => (
                <>
                  {preview(item)}
                  {props.items.length > index + 1 ? ", " : ""}
                </>
              )),
              props.items.length > previewCount && "…",
            ]}
            ]
          </Value>
        </Row>
      </Row>

      <Show when={expanded()}>
        <div class="pt-[1px]">
          <For each={props.items}>
            {(item) => (
              <Row class="pl-8 last:border-b-2">{props.render(item)}</Row>
            )}
          </For>
        </div>
      </Show>
    </>
  );
};

export type PropertyEditorProps = ParentProps<{
  showHeader?: boolean;
  header?: {
    key: string;
    value: string;
  };
}>;

export const PropertyEditorProps = {
  showHeader: true,
  header: {
    key: "Key",
    value: "Value",
  },
};

export const PropertyEditor = (inProps: PropertyEditorProps) => {
  const props = mergeProps(PropertyEditorProps, inProps);

  let tableRef!: HTMLDivElement;

  const [width, setWidth] = makePersisted(createSignal(0.5), {
    storage: sessionStorage,
    name: "property-editor-split-width",
  });
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

      const margin = tableRef.clientWidth * 0.1;

      return Order.clamp(Order.number)({
        minimum: margin,
        maximum: tableRef.clientWidth - margin,
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

  const [hasArray, setHasArray] = createSignal(false);
  const [anyArrayExpanded, setAnyArrayExpanded] = createSignal(false);

  return (
    <PropertyEditorContext.Provider
      value={{
        resizeWidthCssVar,
        hasArray,
        setHasArray,
        anyArrayExpanded,
        setAnyArrayExpanded,
      }}
    >
      <div
        ref={tableRef}
        class="relative w-full border-2 border-b-1 border-theme-border min-w-0 text-nowrap select-text text-sm/tight"
        style={{
          "--col-width": widthPx(),
        }}
      >
        <div
          ref={headerResizeHandleRef}
          class={cn(
            "absolute w-[2px] cursor-col-resize",
            "transition-colors bg-theme-border hover:bg-theme-text",
            resizing() && "bg-theme-text",
            hasArray() && anyArrayExpanded() ? "h-6" : "h-full",
            hasArray() && !props.showHeader && "hidden",
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
          style={{
            left: `calc(var(${resizeWidthCssVar}, var(--col-width)) * 1px)`,
          }}
          onDblClick={() => setWidth(0.5)}
        />

        <Show when={props.showHeader}>
          <div class="w-full border-b-1 border-theme-border text-bold">
            <Row>
              <Key class="ml-0 text-center" noPadding>
                {props.header.key}
              </Key>

              <Value class="px-1 pt-0.5 text-center">
                {props.header.value}
              </Value>
            </Row>
          </div>
        </Show>

        <div>{props.children}</div>
      </div>
    </PropertyEditorContext.Provider>
  );
};

type PropertyEditorContext = {
  resizeWidthCssVar: string;
  hasArray: () => boolean;
  setHasArray: (hasArray: boolean) => void;
  anyArrayExpanded: () => boolean;
  setAnyArrayExpanded: (expanded: boolean) => void;
};

const PropertyEditorContext = createContext<PropertyEditorContext>();
