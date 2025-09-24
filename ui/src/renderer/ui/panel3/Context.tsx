import {
  Component,
  createEffect,
  createSignal,
  ParentProps,
  useContext,
} from "solid-js";
import { createStore, SetStoreFunction } from "solid-js/store";

import createHotStableContext from "~/lib/createHotStableContext";

import { LeafContent, LeafID, LeafRecord, Workspace } from "./data";
import { trackStore } from "@solid-primitives/deep";
import { Console, DateTime, Effect } from "effect";

export type PanelContext = {
  workspace: Workspace;
  setWorkspace: SetStoreFunction<Workspace>;

  leafRecord: LeafRecord;
  setLeafRecord: SetStoreFunction<LeafRecord>;

  historyBatchBegin: () => void;
  historyBatchEnd: () => void;

  getLeafContent: (id: LeafID) => LeafContent;
};
export const PanelContext =
  createHotStableContext<PanelContext>("PanelContext");

export const usePanelContext = (): PanelContext => {
  const ctx = useContext(PanelContext);
  if (!ctx)
    throw new Error(
      "Cannot use PanelContext outside of a PanelContextProvider",
    );
  return ctx;
};

export const PanelContextProvider: Component<
  ParentProps<{
    initialWorkspace: Workspace;
    initialLeafRecord: LeafRecord;
  }>
> = (props) => {
  const [workspace, setWorkspace] = createStore<Workspace>(
    props.initialWorkspace,
  );
  const [leafRecord, setLeafRecord] = createStore<LeafRecord>(
    props.initialLeafRecord,
  );

  const [historyBatch, setHistoryBatch] = createSignal(false);

  createEffect(() => {
    if (historyBatch()) return;

    const update = trackStore(workspace);

    Console.withGroup(
      Effect.gen(function* () {
        console.log(JSON.stringify(update, null, 2));
      }),
      {
        label: `update - ${DateTime.now.pipe(Effect.runSync)}`,
        collapsed: true,
      },
    ).pipe(Effect.runSync);
  });

  const getLeafContent: PanelContext["getLeafContent"] = (id) => {
    const content = leafRecord[id];
    if (!content)
      throw new Error(`Leaf with id '${id}' is not found in leafRecord`);
    return content;
  };

  return (
    <PanelContext.Provider
      value={{
        workspace,
        setWorkspace,

        leafRecord,
        setLeafRecord,

        historyBatchBegin: () => setHistoryBatch(true),
        historyBatchEnd: () => setHistoryBatch(false),

        getLeafContent,
      }}
    >
      {props.children}
    </PanelContext.Provider>
  );
};
