import { createContext } from "solid-js";
import { SetStoreFunction, Store } from "solid-js/store";
import { Option } from "effect";

// import createHotStableContext from "~/lib/createHotStableContext";

import { Leaf, LeafContent, LeafID, LeafRecord, Workspace } from "./data";

export type PanelContext = {
  workspace: Store<Workspace>;
  setWorkspace: SetStoreFunction<Workspace>;

  leafRecord: Store<LeafRecord>;
  setLeafRecord: SetStoreFunction<LeafRecord>;

  historyBatchBegin: () => void;
  historyBatchEnd: () => void;
  historyBatch: <T>(fn: () => T) => T;

  getLeaf: (id: LeafID) => Option.Option<LeafContent>;
  createLeaf: (content?: LeafContent) => Leaf;
};
// export const PanelContext =
//   createHotStableContext<PanelContext>("PanelContext");
export const PanelContext = createContext<PanelContext>();
