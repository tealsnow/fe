import { createContext, VoidComponent } from "solid-js";
import { Data } from "effect";

import UUID from "~/lib/UUID";

export type BarItem = Data.TaggedEnum<{
  divider: {};
  text: {
    value: () => string;
    tooltip: () => string;
  };
  textButton: {
    value: () => string;
    tooltip: () => string;
    onClick: () => void;
  };
  iconButton: {
    icon: VoidComponent;
    tooltip: () => string;
    onClick: () => void;
  };
}>;
export const BarItem = Data.taggedEnum<BarItem>();

export type IdBarItem = BarItem & { id: UUID };

export type Alignment = "left" | "right";

export type BarItemMap = Record<UUID, IdBarItem>;
export type BarItems = Record<Alignment, UUID[]>;

export type StatusBarItemCleanup = () => void;

export type Context = {
  readonly item_map: () => BarItemMap;
  readonly items: () => BarItems;
  addItem: (
    opts: {
      item: BarItem;
      alignment: Alignment;
    } & ({ after?: UUID; before?: never } | { after?: never; before?: UUID }),
  ) => [StatusBarItemCleanup, UUID];
};
export const Context = createContext<Context>();
