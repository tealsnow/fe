import {
  Component,
  createEffect,
  createSignal,
  ParentProps,
  useContext,
} from "solid-js";
import { createStore } from "solid-js/store";
import { LeafRecord, PanelNode, Workspace, WorkspaceSidebar } from "./data";
import { trackStore } from "@solid-primitives/deep";
import { Console, DateTime, Effect, Option } from "effect";

import UUID from "~/lib/UUID";

import { PanelContext } from "./Context";

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
          root: PanelNode.makeLeaf(),
          sidebars: {
            left: WorkspaceSidebar({
              node: PanelNode.makeLeaf(),
            }),
            right: WorkspaceSidebar({
              node: PanelNode.makeLeaf(),
            }),
            bottom: WorkspaceSidebar({
              node: PanelNode.makeLeaf(),
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

  const getLeaf: PanelContext["getLeaf"] = (id) => {
    const content = leafRecord[id];
    if (!content) return Option.none();
    return content;
  };

  const createLeaf: PanelContext["createLeaf"] = (maybeContent) => {
    const content = Option.fromNullable(maybeContent);
    const id = UUID.make();
    setLeafRecord((record) => ({ ...record, [id]: content }));
    return PanelNode.makeLeaf(id);
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
    </PanelContext.Provider>
  );
};
