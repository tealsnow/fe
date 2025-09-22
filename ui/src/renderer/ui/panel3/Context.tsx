import { Component, createEffect, ParentProps, useContext } from "solid-js";
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

export type PanelContextProviderProps = ParentProps<{
  initialWorkspace: Workspace;
  initialLeafRecord: LeafRecord;
}>;
export const PanelContextProvider: Component<PanelContextProviderProps> = (
  props,
) => {
  const [workspace, setWorkspace] = createStore<Workspace>(
    props.initialWorkspace,
  );
  const [leafRecord, setLeafRecord] = createStore<LeafRecord>(
    props.initialLeafRecord,
  );

  createEffect(() => {
    const update = trackStore(workspace);

    Console.withGroup(
      Effect.gen(function* () {
        console.log(JSON.stringify(update, null, 2));
      }),
      {
        label: `createEffect update - ${DateTime.now.pipe(Effect.runSync)}`,
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

        getLeafContent,
      }}
    >
      {props.children}
    </PanelContext.Provider>
  );
};
