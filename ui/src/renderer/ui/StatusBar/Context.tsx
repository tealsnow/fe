import { Brand, Data } from "effect";
import { createContext } from "solid-js";
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
