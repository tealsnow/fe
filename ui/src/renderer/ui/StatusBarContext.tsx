import { Effect, Brand, Data } from "effect";
import { Brand, Data } from "effect";
import {
  batch,
  Component,
  createContext,
  ParentProps,
  useContext,
} from "solid-js";
import { createStore, produce } from "solid-js/store";
import * as uuid from "uuid";
import { IconKind } from "~/assets/icons";

export type StatusBarItem = Data.TaggedEnum<{
  divider: {};
  text: {
    value: () => string;
  };
  textButton: {
    value: () => string;
    onClick: () => void;
  };
  iconButton: {
    icon: () => IconKind;
    onClick: () => void;
  };
}>;
export const StatusBarItem = Data.taggedEnum<StatusBarItem>();

export type IdStatusBarItem = StatusBarItem & { id: StatusBarItemId };

export type StatusBarItemId = string & Brand.Brand<"StatusBarItemId">;
const StatusBarItemIdCtor = Brand.refined<StatusBarItemId>(
  (str) => uuid.validate(str),
  (str) => Brand.error(`expected id ('${str}') to be a uuid`),
);
export const StatusBarItemId = (): StatusBarItemId =>
  StatusBarItemIdCtor(uuid.v4());

export type StatusBarAlignment = "left" | "right";

export type StatusBarItemMap = Record<StatusBarItemId, IdStatusBarItem>;
export type StatusBarItems = Record<StatusBarAlignment, StatusBarItemId[]>;

export type StatusBarItemCleanup = () => void;

export type StatusBarContext = {
  readonly item_map: () => StatusBarItemMap;
  readonly items: () => StatusBarItems;
  addItem: (
    opts: {
      item: StatusBarItem;
      alignment: StatusBarAlignment;
    } & (
      | { after?: StatusBarItemId; before?: never }
      | { after?: never; before?: StatusBarItemId }
    ),
  ) => [StatusBarItemCleanup, StatusBarItemId];
};
export const StatusBarContext = createContext<StatusBarContext>();

export type StatusBarContextProps = ParentProps<{}>;
export const StatusBarContextProvider: Component<StatusBarContextProps> = (
  props,
) => {
  const [store, setStore] = createStore<{
    item_map: StatusBarItemMap;
    items: StatusBarItems;
  }>({
    item_map: {},
    items: {
      left: [],
      right: [],
    },
  });

  return (
    <StatusBarContext.Provider
      value={{
        item_map: () => store.item_map,
        items: () => store.items,

        addItem: (opts) => {
          const id = StatusBarItemId();
          const ided = Object.assign(opts.item, { id });

          batch(() => {
            setStore("item_map", (map) => ({ ...map, [id]: ided }));

            if (opts.after) {
              setStore(
                "items",
                opts.alignment,
                produce((items) => {
                  const idx = items.findIndex((item) => item == opts.after);
                  if (idx !== -1) items.splice(idx, 0, id);
                  else items.push(id);
                }),
              );
            } else if (opts.before) {
              setStore(
                "items",
                opts.alignment,
                produce((items) => {
                  const idx = items.findIndex((item) => item == opts.after);
                  if (idx !== -1) items.splice(idx - 1, 0, id);
                  else items.push(id);
                }),
              );
            } else {
              setStore("items", opts.alignment, (list) => [...list, id]);
            }
          });

          const cleanup = (): void => {
            batch(() => {
              setStore("item_map", (map) => {
                delete map[id];
                return { ...map };
              });
              setStore("items", opts.alignment, (list) =>
                list.filter((item) => item !== id),
              );
            });
          };

          return [cleanup, id];
        },
      }}
    >
      {props.children}
    </StatusBarContext.Provider>
  );
};

export const useStatusBarContext = (): StatusBarContext => {
  const ctx = useContext(StatusBarContext);
  if (!ctx)
    throw new Error(
      "Cannot use StatusBarContext outside of a StatusBarContextProvider",
    );
  return ctx;
};
