import {
  Component,
  createEffect,
  createSignal,
  ParentProps,
  useContext as solidUseContext,
} from "solid-js";
import { createStore } from "solid-js/store";
import { trackStore } from "@solid-primitives/deep";
import { Console, DateTime, Effect, Option } from "effect";

import UUID from "~/lib/UUID";

import {
  LeafRecord,
  makeLeaf,
  PanelNode,
  Workspace,
  WorkspaceSidebar,
} from "../data";

import Context from "./ContextImpl";

export const useContext = (): Context => {
  const ctx = solidUseContext(Context);
  if (!ctx)
    throw new Error(
      "Cannot use PanelContext outside of a PanelContextProvider",
    );
  return ctx;
};

export const ContextProvider: Component<
  ParentProps<{
    initial?: {
      leafRecord: LeafRecord;
      workspace: Workspace;
    };
  }>
> = (props) => {
  const [initialLeafRecord, initialWorkspace] = props.initial
    ? [props.initial.leafRecord, props.initial.workspace]
    : [
        {},
        {
          root: PanelNode.makeTabs(),
          sidebars: {
            left: WorkspaceSidebar({
              node: PanelNode.makeTabs(),
            }),
            right: WorkspaceSidebar({
              node: PanelNode.makeTabs(),
            }),
            bottom: WorkspaceSidebar({
              node: PanelNode.makeTabs(),
            }),
          },
        },
      ];

  const [leafRecord, setLeafRecord] =
    createStore<LeafRecord>(initialLeafRecord);
  const [workspace, setWorkspace] = createStore<Workspace>(initialWorkspace);

  const [historyBatch, setHistoryBatch] = createSignal(false);

  createEffect(() => {
    if (historyBatch()) return;

    const update = trackStore(workspace);

    console.count("panel update");
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

  const getLeaf: Context["getLeaf"] = (id) => {
    const content = leafRecord[id];
    if (!content) return Option.none();
    return content;
  };

  const createLeaf: Context["createLeaf"] = (maybeContent) => {
    const content = Option.fromNullable(maybeContent);
    const id = UUID.make();
    setLeafRecord((record) => ({ ...record, [id]: content }));
    return makeLeaf(id);
  };

  return (
    <Context.Provider
      value={{
        workspace,
        setWorkspace,

        leafRecord,
        setLeafRecord,

        historyBatchBegin: () => setHistoryBatch(true),
        historyBatchEnd: () => setHistoryBatch(false),
        historyBatch: (fn) => {
          setHistoryBatch(true);
          const res = fn();
          setHistoryBatch(false);
          return res;
        },

        getLeaf,
        createLeaf,
      }}
    >
      {props.children}
    </Context.Provider>
  );
};
