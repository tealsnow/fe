import { SetStoreFunction } from "solid-js/store";

import createHotStableContext from "~/lib/createHotStableContext";

import { LeafContent, LeafID, LeafRecord, PanelNode, Workspace } from "./data";
import { Option } from "effect";

export type PanelContext = {
  workspace: Workspace;
  setWorkspace: SetStoreFunction<Workspace>;

  leafRecord: LeafRecord;
  setLeafRecord: SetStoreFunction<LeafRecord>;

  historyBatchBegin: () => void;
  historyBatchEnd: () => void;
  historyBatch: <T>(fn: () => T) => T;

  getLeaf: (id: LeafID) => Option.Option<LeafContent>;
  createLeaf: (content?: LeafContent) => PanelNode.Leaf;
};
export const PanelContext =
  createHotStableContext<PanelContext>("PanelContext");
