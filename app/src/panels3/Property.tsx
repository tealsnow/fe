import * as ef from "effect";
import {
  For,
  Component,
  createSignal,
  Match,
  Switch,
  createEffect,
  JSX,
  Show,
} from "solid-js";
import { cn } from "~/lib/cn";

export type ValueOrFunction<T> = T | (() => T);

export function ValueOrFunction<T>(source: ValueOrFunction<T>): T {
  if (typeof source === "function") {
    return (source as () => T)();
  }
  return source;
}

export type PropertyProps = {
  key: string;
  value: JSX.Element;
};

export const Property = (props: PropertyProps) => {
  return (
    <Tr>
      <Td>{props.key}</Td>
      <Td>{props.value}</Td>
    </Tr>
  );
};

export type StringPropertyProps = {
  key: string;
  value: string;
  format?: (value: string) => string;
  onUpdate?: (newValue: string) => void;
};

export const StringProperty = (props: StringPropertyProps) => {
  const formattedValue = props.format ? props.format(props.value) : props.value;

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
    <Tr class="">
      <Td>{props.key}</Td>
      <Td>
        <input
          ref={inputRef}
          class={cn(
            "flex items-center bg-theme-background ring-0 min-w-0 min-h-0 h-full w-full box-border border border-transparent p-0",
            editing() && "border-theme-colors-purple-border",
          )}
          size={1} // required for min-w to work
          type="text"
          readOnly={!editing()}
          name={props.key}
          value={editing() ? editValue() : formattedValue}
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
      </Td>
      <Show when={props.onUpdate}>
        <Td
          class={cn(
            "text-center hover:bg-theme-colors-blue-background",
            editing() && "bg-theme-colors-blue-background",
          )}
          onClick={() => setEditing((val) => !val)}
        >
          E
        </Td>
      </Show>
    </Tr>
  );
};

export type PropertyEditorProps = {
  properties: JSX.Element[]; // `Property`
};

type TrProps = JSX.HTMLAttributes<HTMLTableRowElement>;
const Tr = (props: TrProps) => (
  <tr
    {...props}
    class={cn("border-t border-b border-theme-border", props.class)}
  />
);

type TdProps = JSX.HTMLAttributes<HTMLTableCellElement>;
const Td = (props: TdProps) => (
  <td
    {...props}
    class={cn("border-r border-l border-theme-border", props.class)}
  />
);

// const Tr = styled.tr("border-t border-b border-theme-border");

// // const Th = styled.th("px-1 border-r border-l border-theme-border");
// const Td = styled.td("border-r border-l border-theme-border");

export const PropertyEditor = (props: PropertyEditorProps) => {
  return (
    <table class="table-auto w-full min-w-max border-2">
      {/*<thead class="border-b-2 border-theme-border">
        <Tr>
          <Th>Key</Th>
          <Th>Value</Th>
        </Tr>
      </thead>*/}
      <tbody>
        <For each={props.properties}>{(property) => <>{property}</>}</For>
      </tbody>
    </table>
  );
};
