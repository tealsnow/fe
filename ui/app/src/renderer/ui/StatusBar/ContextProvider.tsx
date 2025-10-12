import {
  batch,
  Component,
  ParentProps,
  useContext as solidUseContext,
} from "solid-js";
import { createStore, produce } from "solid-js/store";

import UUID from "~/lib/UUID";

import { Context, BarItemMap, BarItems } from "./Context";

export const Provider: Component<ParentProps<{}>> = (props) => {
  const [store, setStore] = createStore<{
    item_map: BarItemMap;
    items: BarItems;
  }>({
    item_map: {},
    items: {
      left: [],
      right: [],
    },
  });

  return (
    <Context.Provider
      value={{
        item_map: () => store.item_map,
        items: () => store.items,

        addItem: (opts) => {
          const id = UUID.make();
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
    </Context.Provider>
  );
};

export const useContext = (): Context => {
  const ctx = solidUseContext(Context);
  if (!ctx)
    throw new Error(
      "Cannot use StatusBar Context outside of a StatusBar Context Provider",
    );
  return ctx;
};
