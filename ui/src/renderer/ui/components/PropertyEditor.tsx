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
  Component,
  JSXElement,
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
import { Icon, icons } from "~/assets/icons";
import { TextInputLozenge } from "~/ui/components/Lozenge";
import Button from "~/ui/components/Button";

type RowProps = JSX.HTMLAttributes<HTMLDivElement>;
const Row: Component<RowProps> = (props) => {
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
const Key: Component<KeyProps> = (inProps) => {
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

type ValueProps = JSX.HTMLAttributes<HTMLDivElement>;
const Value: Component<ValueProps> = (props) => {
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

type PropertyEditorContext = {
  resizeWidthCssVar: string;
  hasArray: () => boolean;
  setHasArray: (hasArray: boolean) => void;
  anyArrayExpanded: () => boolean;
  setAnyArrayExpanded: (expanded: boolean) => void;
};

const PropertyEditorContext = createContext<PropertyEditorContext>();

export type PropertyEditorRootProps = ParentProps<{
  name: string;
  showHeader?: boolean;
  header?: {
    key: string;
    value: string;
  };
}>;
export const PropertyEditorRootProps = {
  showHeader: true,
  header: {
    key: "Key",
    value: "Value",
  },
};
export const PropertyEditorRoot: Component<PropertyEditorRootProps> = (
  inProps,
) => {
  const props = mergeProps(PropertyEditorRootProps, inProps);

  let tableRef!: HTMLDivElement;

  // false positive
  // eslint-disable-next-line solid/reactivity
  const [width, setWidth] = makePersisted(createSignal(0.3), {
    storage: sessionStorage,
    // eslint-disable-next-line solid/reactivity
    name: `property-editor-split-width-'${props.name}'`,
  });
  const [widthPx, setWidthPx] = createSignal<number>(0);
  const updateWidthPx = (): number =>
    setWidthPx(width() * tableRef.clientWidth);
  createEffect(() => updateWidthPx());

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

export type StringPropertyProps = {
  key: string;
  value: string;
  valueClass?: string;
  format?: (value: string) => string;
  onUpdate?: (newValue: string) => void;
};
export const StringProperty: Component<StringPropertyProps> = (props) => {
  const formattedValue = (): string =>
    props.format ? props.format(props.value) : props.value;

  const [editing, setEditing] = createSignal(false);
  // eslint-disable-next-line solid/reactivity
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
        <TextInputLozenge
          ref={inputRef}
          color={editing() ? "purple" : "blue"}
          size="small"
          disabled={props.onUpdate === undefined ? "" : undefined}
          class={cn(
            "w-full h-full pt-0.5 overflow-visible overflow-ellipsis",
            props.valueClass,
          )}
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
        />
      </Value>
    </Row>
  );
};

export type ButtonPropertyProps = ParentProps<{
  key: string;
  onClick?: () => void;
}>;
export const ButtonProperty: Component<ButtonPropertyProps> = (props) => {
  return (
    <Row>
      <Key>{props.key}</Key>

      <Value>
        <Button
          as="span"
          color="aqua"
          size="small"
          class="w-full h-full pt-1 whitespace-nowrap text-ellipsis min-w-0 max-w-full"
          disabled={props.onClick === undefined}
          onClick={props.onClick}
        >
          {props.children}
        </Button>
      </Value>
    </Row>
  );
};

export type EnumPropertyProps<T> = {
  key: string;
  value: T;
  options: T[];
  onChange: (value: T) => void;
  render?: (value: T) => JSXElement;
};

export const EnumPropertyProps = {
  render: (value: any) => <>{value}</>,
};

export const EnumProperty = <T,>(inProps: EnumPropertyProps<T>): JSXElement => {
  const props = mergeProps(EnumPropertyProps, inProps);

  return (
    <Row>
      <Key>{props.key}</Key>

      <Value class="flex gap-[1px]">
        <For each={props.options}>
          {(option) => (
            <Button
              class="grow h-full pt-1"
              color="green"
              size="small"
              variant={props.value === option ? "default" : "outline"}
              onClick={() => props.onChange(option)}
            >
              {props.render(option as any)}
            </Button>
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
  render: (item: T) => JSXElement;
  preview?: (item: T) => JSXElement;
  last?: () => JSXElement;
};

export const ArrayProperty = <T,>(props: ArrayPropertyProps<T>): JSXElement => {
  const preview = (): ((item: T) => JSXElement) =>
    props.preview ?? props.render;
  const previewCount = (): number => props.previewCount ?? 3;

  const context = useContext(PropertyEditorContext)!;
  onMount(() => context.setHasArray(true));

  // false positive
  // eslint-disable-next-line solid/reactivity
  const [expanded, setExpanded] = makePersisted(createSignal(false), {
    storage: sessionStorage,
    // eslint-disable-next-line solid/reactivity
    name: `array-property-expanded-'${props.key}'`,
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
              <Icon
                icon={icons["chevron_right"]}
                class="fill-transparent size-3 p-0"
              />
            </button>
            <div class={cn("pt-1", expanded() && "pt-0.5")}>{props.key}</div>
          </Key>

          <Value
            class={cn(
              "h-full overflow-clip flex items-center",
              expanded() && "pt-0 pb-[2px]",
            )}
          >
            <span class="text-theme-deemphasis">
              [
              {[
                props.items.slice(0, previewCount()).map((item, index) => (
                  <>
                    <span class="text-theme-text">{preview()(item)}</span>
                    {props.items.length > index + 1 ? ", " : ""}
                  </>
                )),
                props.items.length > previewCount() && "…",
              ]}
              ]
            </span>
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
          <Show when={props.last}>
            <Row class="pl-8 last:border-b-2">{props.last!()}</Row>
          </Show>
        </div>
      </Show>
    </>
  );
};

export type AddStringProps = {
  placeholder?: string;
  defaultValue?: string;
  onSubmit: (value: string) => void;
};

export const AddString: Component<AddStringProps> = (props) => {
  let inputRef!: HTMLInputElement;
  const [value, setValue] = createSignal<string | null>(null);
  const onSubmit = (): void => {
    const val = value();
    if (!val) return;

    props.onSubmit(val);

    setValue(null);
  };

  return (
    <div class="flex h-full gap-1">
      <Show when={value() !== null}>
        <TextInputLozenge
          ref={inputRef}
          color="purple"
          size="small"
          class="h-full"
          // class={cn(
          //   "ring-0 min-h-0 h-full p-0 px-1 pt-0.5 box-border bg-theme-colors-purple-background border border-theme-colors-purple-border",
          // )}
          placeholder={props.placeholder}
          value={value()!}
          onBlur={() => setTimeout(() => setValue(null), 100)}
          onInput={({ currentTarget: { value } }) => setValue(value)}
          onKeyDown={({ key }) => {
            switch (key) {
              case "Enter":
                onSubmit();
                break;
              case "Escape":
                setValue(null);
                break;
            }
          }}
        />
      </Show>
      <Button
        class="h-full"
        size="icon"
        color="green"
        noOnClickToOnMouseDown
        onClick={() => {
          if (value() !== null) {
            onSubmit();
          } else {
            setValue(props.defaultValue ?? "");
            inputRef.focus();
            inputRef.select();
          }
        }}
      >
        <Icon icon={icons["add"]} />
      </Button>
    </div>
  );
};

export const PropertyEditor = Object.assign(PropertyEditorRoot, {
  String: StringProperty,
  Button: ButtonProperty,
  Enum: EnumProperty,
  Array: ArrayProperty,
  AddString: AddString,
});
export default PropertyEditor;
