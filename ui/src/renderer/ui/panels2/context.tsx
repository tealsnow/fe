import {
  Accessor,
  batch,
  Component,
  Context,
  createContext,
  createEffect,
  createSignal,
  ParentProps,
  useContext,
} from "solid-js";
import { createStore } from "solid-js/store";
import { trackStore } from "@solid-primitives/deep";

import { DateTime, Effect, Number, Option, Order, pipe } from "effect";

import assert from "~/lib/assert";
import Percent from "~/lib/Percent";
import Integer from "~/lib/Integer";
import OutOfBoundsError from "~/lib/OutOfBoundsError";
import createHotStableContext from "~/lib/createHotStableContext";

import { setupRoot } from "./root";
import Panel from "./Panel";

export type PanelContext = {
  tree: Panel.Tree;

  addNode: (node: Panel.Node) => Panel.Node;
  addNodes: (...node: Panel.Node[]) => Panel.Node[];
  getRoot: () => Panel.Node.Root;
  getNode: <T extends Panel.ID["_tag"]>(
    id: Extract<Panel.ID, { _tag: T }>,
  ) => Effect.Effect<Extract<Panel.Node, { _tag: T }>, Panel.DoesNotExistError>;

  addChild: (opts: {
    dockSpace: Panel.ID.DockSpace;
    child: Panel.ID;
  }) => Effect.Effect<void, Panel.AddChildError>;

  selectTab: (opts: {
    dockSpace: Panel.ID.DockSpace;
    index: Option.Option<Integer>;
  }) => Effect.Effect<
    void,
    | Panel.DoesNotExistError
    | Panel.DockSpaceIsNotTabsLayoutError
    | OutOfBoundsError
  >;

  undo: () => void;
  redo: () => void;

  showDebugSidePanel: Accessor<boolean>;
  toggleDebugSidePanel: () => void;
};
// export const PanelContext = createContext<PanelContext>();
export const PanelContext =
  createHotStableContext<PanelContext>("PanelContext");

export const usePanelContext = (): PanelContext => {
  const ctx = useContext(PanelContext);
  if (!ctx)
    throw new Error(
      "cannot use PanelContext outside of a PanelContextProvider",
    );
  return ctx;
};

export type PanelContextProviderProps = ParentProps<{}>;
export const PanelContextProvider: Component<PanelContextProviderProps> = (
  props,
) => {
  const rootId = Panel.ID.DockSpace();

  const [nodesStore, setNodesStore] = createStore<Panel.NodeStore>({});

  const addNode: PanelContext["addNode"] = (node) => {
    setNodesStore((nodes) => ({ ...nodes, [node.id.uuid]: node }));
    return node;
  };

  const addNodes: PanelContext["addNodes"] = (...nodes) => {
    batch(() => {
      for (const node of nodes) addNode(node);
    });
    return nodes;
  };

  const getRoot: PanelContext["getRoot"] = () => {
    const node = nodesStore[rootId.uuid];
    assert(Panel.Node.canBeRoot(node));
    return node;
  };

  const getNode = <T extends Panel.ID["_tag"]>(
    id: Extract<Panel.ID, { _tag: T }>,
  ): Effect.Effect<Extract<Panel.Node, { _tag: T }>, Panel.DoesNotExistError> =>
    // eslint-disable-next-line solid/reactivity
    Effect.gen(function* () {
      const node = nodesStore[id.uuid];

      if (node === undefined)
        return yield* Effect.fail(new Panel.DoesNotExistError({ id }));
      assert(node._tag === id._tag);

      return node as Extract<Panel.Node, { _tag: T }>;
    });

  const addChild: PanelContext["addChild"] = ({
    dockSpace: dockSpaceId,
    child: childId,
  }) =>
    Effect.gen(function* () {
      const dockSpace = yield* getNode(dockSpaceId);
      const child = yield* getNode(childId);

      if (Option.isSome(child.parent))
        return yield* Effect.fail(
          new Panel.AlreadyHasParentError({
            id: childId,
            existing: Option.getOrThrow(child.parent),
            addingTo: dockSpace.id,
          }),
        );

      yield* Panel.Node.DockSpaceLayout.$match({
        // Slotted are a special case, they must provide a method 'addChild'
        // to allow for adding children. If not set then we error out
        Slotted: (slotted) =>
          Option.map(slotted.addChild, (addChild) =>
            batch(() => addChild(child)),
          ).pipe(
            Option.getOrElse(() =>
              // addChild was None, so error out
              Effect.fail(
                new Panel.DoesNotAcceptChildError({
                  id: childId,
                  parent: dockSpace.id,
                  reason:
                    "This Slotted layout DockSpace does not allow adding children",
                }),
              ),
            ),
          ),
        // Tabs only allow leaf children
        Tabs: () =>
          Effect.gen(function* () {
            if (Panel.Node.$is("DockSpace")(child))
              // child is a DockSpace, so error out
              return yield* Effect.fail(
                new Panel.DoesNotAcceptChildError({
                  id: childId,
                  parent: dockSpace.id,
                  reason: "Cannot add DockSpace child to Tabs layout DockSpace",
                }),
              );

            // add child and set its parent
            batch(() => {
              setNodesStore(dockSpace.id.uuid, (dockSpace) => {
                assert(Panel.Node.$is("DockSpace")(dockSpace));
                assert(
                  Panel.Node.DockSpaceLayout.$is("Tabs")(dockSpace.layout),
                );

                return {
                  ...dockSpace,
                  layout: {
                    ...dockSpace.layout,
                    children: [...dockSpace.layout.children, child.id],
                  },
                };
              });
              setNodesStore(child.id.uuid, (child) => ({
                ...child,
                parent: Option.some(dockSpace.id),
              }));
            });
          }),
        // by far the most complex for the percentage handling
        Split: (split) =>
          batch(() =>
            Effect.gen(function* () {
              const n = split.children.length;

              let sum = 0;
              for (const { percent } of split.children) {
                sum += percent;
              }

              // work out the new child's percent size
              const percentNew = pipe(
                1 / (n + 1),
                Order.clamp(Order.number)({ minimum: 0, maximum: 1 }),
              );

              const addChildToParent = (percent: Percent): void => {
                setNodesStore(dockSpace.id.uuid, (dockSpace) => {
                  assert(Panel.Node.$is("DockSpace")(dockSpace));
                  assert(
                    Panel.Node.DockSpaceLayout.$is("Split")(dockSpace.layout),
                  );

                  return {
                    ...dockSpace,
                    layout: {
                      ...dockSpace.layout,
                      children: [
                        ...dockSpace.layout.children,
                        { percent, child: child.id },
                      ],
                    },
                  };
                });
              };
              const setChildParent = (): void => {
                setNodesStore(child.id.uuid, (child) => ({
                  ...child,
                  parent: Option.some(dockSpace.id),
                }));
              };

              const pushChild = (percent: Percent): void => {
                addChildToParent(percent);
                setChildParent();
              };

              // if sum is less than 0, either we have no children
              // or its in an invalid state
              if (sum <= 0) {
                if (n === 0) {
                  // no children yet, so just add the child
                  pushChild(Percent(1));
                  return Effect.succeed(void {});
                }

                // children sizes are broken, so fix them
                const each = (1 - percentNew) / n;

                setNodesStore(dockSpace.id.uuid, (dockSpace) => {
                  assert(Panel.Node.$is("DockSpace")(dockSpace));
                  assert(
                    Panel.Node.DockSpaceLayout.$is("Split")(dockSpace.layout),
                  );

                  const children: { percent: Percent; child: Panel.ID }[] = [];
                  for (const { child } of split.children) {
                    children.push({ percent: Percent(each), child });
                  }

                  return {
                    ...dockSpace,
                    layout: {
                      ...dockSpace.layout,
                      children,
                    },
                  };
                });
                pushChild(Percent(percentNew));

                return Effect.succeed(void {});
              }

              // work out by how much to adjust each child
              const scale = (1 - percentNew) / sum;

              // adjust each child
              setNodesStore(dockSpace.id.uuid, (dockSpace) => {
                assert(Panel.Node.$is("DockSpace")(dockSpace));
                assert(
                  Panel.Node.DockSpaceLayout.$is("Split")(dockSpace.layout),
                );

                const children: { percent: Percent; child: Panel.ID }[] = [];
                for (const { percent, child } of split.children) {
                  children.push({ percent: Percent(percent * scale), child });
                }

                return {
                  ...dockSpace,
                  layout: {
                    ...dockSpace.layout,
                    children,
                  },
                };
              });
              // add new child
              pushChild(Percent(percentNew));

              return Effect.succeed(void {});
            }),
          ),
      })(dockSpace.layout);
    });

  const selectTab: PanelContext["selectTab"] = ({
    dockSpace: dockSpaceId,
    index,
  }) =>
    Effect.gen(function* () {
      const dockSpace = yield* getNode(dockSpaceId);

      if (!Panel.Node.DockSpaceLayout.$is("Tabs")(dockSpace.layout))
        return yield* Effect.fail(
          new Panel.DockSpaceIsNotTabsLayoutError({ dockSpace: dockSpace.id }),
        );

      if (Option.isSome(index)) {
        const idx = Option.getOrThrow(index);
        if (idx < 0 || idx > dockSpace.layout.children.length)
          return yield* Effect.fail(new OutOfBoundsError({ index: idx }));
      }

      const isEqual = Option.getEquivalence(Number.Equivalence);
      if (isEqual(dockSpace.layout.active, index)) return;

      setNodesStore(dockSpace.id.uuid, (dockSpace) => {
        assert(Panel.Node.$is("DockSpace")(dockSpace));
        assert(Panel.Node.DockSpaceLayout.$is("Tabs")(dockSpace.layout));

        return {
          ...dockSpace,
          layout: {
            ...dockSpace.layout,
            active: index,
          },
        };
      });
    });

  let historyChange = false;

  const history: Panel.NodeStore[] = [];
  let historyIndex = 0;

  createEffect(() => {
    const newNodes = trackStore(nodesStore);

    if (historyChange) {
      console.groupCollapsed("history change");

      console.groupCollapsed("new nodes");
      console.log(JSON.stringify(newNodes, null, 2));
      console.groupEnd();

      console.groupCollapsed("history");
      console.log(JSON.stringify(history, null, 2));
      console.groupEnd();

      console.groupEnd();

      historyChange = false;
      return;
    }

    const time = DateTime.now.pipe(Effect.runSync);
    console.group(`nodes update -- ${time}`);
    console.count("nodes update / count");

    console.groupCollapsed("update");
    console.log(JSON.stringify(newNodes, null, 2));
    console.groupEnd();

    console.groupEnd();

    history.push({ ...newNodes });
    historyIndex += 1;

    console.groupCollapsed("history");
    console.log(JSON.stringify(history, null, 2));
    console.groupEnd();
  });

  const undo = (): void => {
    if (history.length === 0) return;
    console.log("undo");

    historyIndex -= 1;

    historyChange = true;
    setNodesStore(history[historyIndex - 1]);

    console.groupCollapsed("set");
    console.log(JSON.stringify(nodesStore, null, 2));
    console.groupEnd();
  };
  const redo = (): void => {
    //
  };

  const [showDebugSidePanel, setShowDebugSidePanel] = createSignal(true);

  return (
    <PanelContext.Provider
      value={{
        tree: {
          root: rootId,
          nodes: nodesStore,
          setNodes: setNodesStore,
        },

        addNode,
        addNodes,
        getRoot,
        getNode,

        addChild,
        selectTab,

        undo,
        redo,

        showDebugSidePanel,
        toggleDebugSidePanel: () => setShowDebugSidePanel((b) => !b),
      }}
    >
      <SetupRoot>{props.children}</SetupRoot>
    </PanelContext.Provider>
  );
};

type SetupRootProps = ParentProps<{}>;
const SetupRoot: Component<SetupRootProps> = (props) => {
  setupRoot();
  return <>{props.children}</>;
};
