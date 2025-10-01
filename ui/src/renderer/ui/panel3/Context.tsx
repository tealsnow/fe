import { createContext } from "solid-js";
import { SetStoreFunction, Store } from "solid-js/store";
import { Option } from "effect";

import UUID from "~/lib/UUID";
// import createHotStableContext from "~/lib/createHotStableContext";

import { Leaf, LeafContent, LeafRecord, Workspace } from "./data";

export type PanelContext = {
  workspace: Store<Workspace>;
  setWorkspace: SetStoreFunction<Workspace>;

  leafRecord: Store<LeafRecord>;
  setLeafRecord: SetStoreFunction<LeafRecord>;

  historyBatchBegin: () => void;
  historyBatchEnd: () => void;
  historyBatch: <T>(fn: () => T) => T;

  getLeaf: (id: UUID) => Option.Option<LeafContent>;
  createLeaf: (content?: LeafContent) => Leaf;
};
// export const PanelContext =
//   createHotStableContext<PanelContext>("PanelContext");
export const PanelContext = createContext<PanelContext>();
