import { For, Match, Switch } from "solid-js";
import { Component, createRoot } from "solid-js";
import { createStore } from "solid-js/store";

import { EnumMap } from "~/lib/type_helpers";
import { storeObjectFromStore } from "~/lib/SignalObject";
import Button from "./ui/components/Button";

export type StatusBarAlignment = "left" | "right";

export interface StatusBarProps {
  id: string;
  kind: "text" | "button";
  alignment: StatusBarAlignment;
}

export type StatusBarItem = Readonly<StatusBarProps> & {
  content: Component;
  onClick?: () => void; // only valid for `kind: "button"`
};

export type StatusBarItems = EnumMap<
  StatusBarAlignment,
  Record<string, StatusBarItem>
>;

export interface StatusBarInterface {
  items: StatusBarItems;
  createItem: (props: StatusBarProps) => StatusBarItem;
}

const itemsStore = createRoot(() =>
  storeObjectFromStore(
    createStore<StatusBarItems>({
      left: {},
      right: {},
    }),
  ),
);

export const statusBar: StatusBarInterface = {
  items: itemsStore.val,
  createItem: (props: StatusBarProps): StatusBarItem => {
    // @NOTE: This is to avoid duplication during dev/hmr
    //   if an item need to be re-inserted, i.e. changes side,
    //   a full refresh is required
    const existing = itemsStore.val[props.alignment][props.id];
    if (existing) return existing;

    const item: StatusBarItem = {
      content: () => <></>,
      ...props,
    };
    itemsStore.set(props.alignment, props.id, item);

    return item;
  },
};

export const StatusBar = () => {
  const iface = statusBar;

  return (
    <>
      <div class="border-theme-border bg-theme-statusbar-background mt-auto flex h-6 flex-row items-center border-t p-0.5 px-2 text-xs">
        <RenderItems items={iface.items.left} />

        <div class="ml-auto">
          <RenderItems items={iface.items.right} />
        </div>
      </div>
    </>
  );
};

const RenderItems = (props: { items: { [key: string]: StatusBarItem } }) => {
  return (
    <For each={Object.entries(props.items)}>
      {([_id, item]) => <RenderItem item={item} />}
    </For>
  );
};

const RenderItem = (props: { item: StatusBarItem }) => {
  return (
    <Switch>
      <Match when={props.item.kind === "text"}>
        <div class="px-0.5">{props.item.content({})}</div>
      </Match>
      <Match when={props.item.kind === "button"}>
        {/*<button
          class="hover:bg-theme-icon-base-fill active:bg-theme-icon-active-fill cursor-pointer rounded-sm p-0.5"
          onClick={() => {
            props.item.onClick?.call({});
          }}
        >
          {props.item.content({})}
        </button>*/}
        <Button
          variant="icon"
          size="icon"
          onClick={() => props.item.onClick?.call({})}
        >
          {props.item.content({})}
        </Button>
      </Match>
    </Switch>
  );
};

export default StatusBar;
