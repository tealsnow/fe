import * as uuid from "uuid";
import { Brand, Cause, Data, Effect, Match, Option, Order, pipe } from "effect";
import * as tsafe from "tsafe";
import { SetStoreFunction } from "solid-js/store";
import { Component } from "solid-js";

import { PickOptional } from "~/lib/type_helpers";
import { storeUpdate } from "~/lib/SignalObject";
import OptionGetOrFail from "~/lib/OptionGetOrFail";

export namespace ID {
  // @NOTE: please take careful note not to compare ids by themselves
  //   i.e. `id1 === id2` rather use `id1.uuid === id2.uuid`
  //   otherwise they will always result in false
  //
  //   Heed my warning, I have lost many hours debugging issues caused by this
  //   God a wish I could overload the equality operator,
  //   why does the simple way not work, its not that the tags are not equal
  //   the `JSON.stringify` will be literally be exactly the same so why

  export type IDBase = string & Brand.Brand<"NodeID">;
  export const IDBase = Brand.refined<IDBase>(
    (s) => uuid.validate(s),
    (s) => Brand.error(`Expected ${s} to be a valid UUID`),
  );

  export type Map = {
    parent: { uuid: IDBase };
    leaf: { uuid: IDBase };
  };
  export type Tag = keyof Map;

  export type TaggedMap = {
    [K in keyof Map]: { readonly _tag: K } & Map[K];
  };

  export type Of<K extends Tag> = TaggedMap[K];

  export type Parent = Of<"parent">;
  export type Leaf = Of<"leaf">;

  export const $is =
    <T extends Tag>(tag: T) =>
    (id: ID): id is Of<T> => {
      return id._tag === tag;
    };

  export const $match =
    <R>(map: { [K in Tag]: () => R }) =>
    (id: ID): R => {
      switch (id._tag) {
        case "parent":
          return map.parent();
        case "leaf":
          return map.leaf();
      }
    };

  export const create = {
    Parent: Effect.sync<Parent>(() => ({
      _tag: "parent",
      uuid: IDBase(uuid.v4()),
    })),
    Leaf: Effect.sync<Leaf>(() => ({
      _tag: "leaf",
      uuid: IDBase(uuid.v4()),
    })),
  };
}
export type ID = ID.TaggedMap[ID.Tag];

export type Percent = number & Brand.Brand<"Percent">;
export const Percent = Brand.refined<Percent>(
  (n) => Number.isFinite(n) && n >= 0 && n <= 1,
  (n) => Brand.error(`Expected ${n} to be a percentage`),
);

export namespace Layout {
  export type SplitDirection = "vertical" | "horizontal";

  export const crossDirection = (direction: SplitDirection): SplitDirection =>
    direction === "vertical" ? "horizontal" : "vertical";

  export type Map = {
    split: {
      children: ID[];
      direction: SplitDirection;
    };
    tabs: {
      children: ID.Leaf[];
      active: Option.Option<ID.Leaf>;
    };
  };
  export type Tag = keyof Map;

  export type TaggedMap = {
    [K in Tag]: { readonly _tag: K } & Map[K];
  };

  export type Of<K extends Tag> = TaggedMap[K];

  export type Split = Of<"split">;
  export type Tabs = Of<"tabs">;

  export const Split = ({
    children = [],
    direction,
  }: {
    children?: ID[];
    direction: SplitDirection;
  }): Split => ({
    _tag: "split",
    children,
    direction,
  });
  export const Tabs = ({
    children = [],
    active = Option.none(),
  }: {
    children?: ID.Leaf[];
    active?: Option.Option<ID.Leaf>;
  } = {}): Tabs => ({
    _tag: "tabs",
    children,
    active,
  });

  export const $is =
    <T extends Tag>(tag: T) =>
    (layout: Layout): layout is Of<T> => {
      return layout._tag === tag;
    };

  export const $as =
    <T extends Tag>(tag: T) =>
    (layout: Layout): Option.Option<TaggedMap[T]> => {
      if ($is(tag)(layout)) return Option.some(layout);
      return Option.none();
    };
}
export type Layout = Layout.TaggedMap[Layout.Tag];

export namespace Node {
  export namespace Data {
    export type EdgeDropConfig = {
      left: boolean;
      right: boolean;
      top: boolean;
      bottom: boolean;
    };
    export const EdgeDropConfig = (): EdgeDropConfig =>
      ({
        left: true,
        right: true,
        top: true,
        bottom: true,
      }) as const;

    export type Common = {
      id: ID;
      parent?: Option.Option<ID.Parent>;
      percentOfParent?: Percent;
      edgeDropConfig?: EdgeDropConfig;
    };
    export const Common = (): Required<PickOptional<Common>> =>
      ({
        parent: Option.none(),
        percentOfParent: Percent(1),
        edgeDropConfig: EdgeDropConfig(),
      }) as const;

    export type ParentProps = Common & {
      id: ID.Parent;
      layout?: Layout;
      titlebar?: Option.Option<Component<{}>>;
    };
    export const ParentProps = (): Required<PickOptional<ParentProps>> =>
      ({
        layout: Layout.Split({ direction: "horizontal" }),
        titlebar: Option.none(),
        ...Common(),
      }) as const;
    export type Parent = Required<ParentProps>;

    export type LeafProps = Common & {
      id: ID.Leaf;
      title: string;
      content?: Option.Option<Component<{}>>;
    };
    export const LeafProps = (): Required<PickOptional<LeafProps>> =>
      ({
        content: Option.none(),
        ...Common(),
      }) as const;
    export type Leaf = Required<LeafProps>;
  }

  export type Map = {
    parent: Data.Parent;
    leaf: Data.Leaf;
  };
  export type Tag = keyof Map;
  tsafe.assert<tsafe.Equals<Tag, ID.Tag>>();

  export type TaggedMap = {
    [K in keyof Map]: { readonly _tag: K } & Map[K];
  };

  export type Of<K extends Tag> = TaggedMap[K];

  export type Parent = Of<"parent">;
  export type Leaf = Of<"leaf">;
  tsafe.assert<tsafe.Extends<Parent, Node>>();
  tsafe.assert<tsafe.Extends<Leaf, Node>>();

  export const $is =
    <T extends Tag>(tag: T) =>
    (node: Node): node is Of<T> => {
      return node._tag === tag;
    };

  export const $as =
    <T extends Tag>(tag: T) =>
    (node: Node): Option.Option<TaggedMap[T]> => {
      if ($is(tag)(node)) return Option.some(node);
      return Option.none();
    };

  export const $match =
    <R>(map: { [K in Tag]: () => R }) =>
    (node: Node): R => {
      switch (node._tag) {
        case "parent":
          return map.parent();
        case "leaf":
          return map.leaf();
      }
    };

  export type ParentProps = Data.ParentProps & PickOptional<Data.ParentProps>;
  export type LeafProps = Data.LeafProps & PickOptional<Data.LeafProps>;

  export const get = (tree: Tree, { id }: { id: ID }): Option.Option<Node> => {
    const node = tree.nodes[id.uuid];
    if (node === undefined) return Option.none();
    return Option.some(node);
  };

  export const getOrError = (
    tree: Tree,
    { id, gettingParentId: parentId }: { id: ID; gettingParentId?: ID.Parent },
  ): Effect.Effect<Node, NodeNotInTreeError> =>
    Effect.gen(function* () {
      const node = get(tree, { id });
      if (Option.isNone(node))
        yield* Effect.fail(new NodeNotInTreeError({ id })).pipe(
          Effect.mapError((err) =>
            Match.value(err).pipe(
              Match.tag("NodeNotInTreeError", (err) =>
                parentId ? err.withParent(parentId) : err,
              ),
              Match.exhaustive,
            ),
          ),
        );
      return Option.getOrThrow(node);
    });

  export const update = (
    setTree: SetTree,
    { id, props }: { id: ID; props: Partial<Omit<Data.Common, "id">> },
  ): Effect.Effect<void, NodeNotInTreeError> =>
    storeUpdate(setTree, (tree) =>
      Effect.gen(function* () {
        const node = yield* Node.getOrError(tree, { id });
        tree.nodes[id.uuid] = { ...node, ...props };
        yield* Effect.succeed(void {});
      }),
    );

  /**
   * re-parents a node, removing it from its parent if any and adding it to the
   * given
   *
   * If no `idx` is given it will append otherwise insert it at the `idx`
   */
  export const reParent = (
    setTree: SetTree,
    {
      id,
      newParentId,
      idx,
    }: { id: ID.Leaf; newParentId: ID.Parent; idx?: number },
  ): Effect.Effect<
    void,
    NodeNotInTreeError | NodeHasNoParentError | CannotDeleteRootError
  > =>
    storeUpdate(setTree, (tree) =>
      Effect.gen(function* () {
        const node = yield* Node.getOrError(tree, { id });

        const oldParentId = yield* OptionGetOrFail(
          node.parent,
          () => new NodeHasNoParentError({ id }),
        );
        const oldParent = yield* Node.Parent.getOrError(tree, {
          parentId: oldParentId,
        });

        const newParent = yield* Node.Parent.getOrError(tree, {
          parentId: newParentId,
        });

        // remove from old parent
        oldParent.layout.children = oldParent.layout.children.filter(
          (childId) => childId.uuid !== id.uuid,
        );

        // add to new parent
        if (idx !== undefined) {
          newParent.layout.children.splice(idx, 0, id);
        } else {
          newParent.layout.children.push(id);
        }
        node.parent = Option.some(newParentId);

        // update active
        if (Layout.$is("tabs")(oldParent.layout)) {
          const tabs = oldParent.layout;

          if (
            Option.map(tabs.active, (active) => active.uuid === id.uuid).pipe(
              Option.getOrElse(() => false),
            )
          ) {
            tabs.active = Option.none();
          }
        }
        if (Layout.$is("tabs")(newParent.layout)) {
          const tabs = newParent.layout;
          tabs.active = Option.some(id);
        }

        // fix children %
        yield* Node.Parent.redistributeChildren(setTree, {
          parentId: oldParentId,
        });
        yield* Node.Parent.redistributeChildren(setTree, {
          parentId: newParentId,
        });

        // collapse nested unary parents
        if (oldParent.layout.children.length === 1) {
          const childId = oldParent.layout.children[0];
          Match.value(childId).pipe(
            Match.tag("parent", (parentId) =>
              Effect.gen(function* () {
                const child = yield* Node.Parent.getOrError(tree, { parentId });
                if (child.layout.children.length === 0) {
                  yield* Node.destroy(setTree, { id: childId });
                }
              }),
            ),
            Match.tag("leaf", (leafId) =>
              Effect.gen(function* () {
                if (!Option.isSome(oldParent.parent)) return;

                yield* Node.reParent(setTree, {
                  id: leafId,
                  newParentId: oldParent.parent.value,
                });
              }),
            ),
            Match.exhaustive,
          );
        }
      }),
    );

  /**
   * Replaces a panel with the given panel.
   *
   * The new panel will be removed from its parent if it has one
   * and the replaced panel will loose its parent
   */
  export const replaceWith = (
    setTree: SetTree,
    { toReplace, with: replacement }: { toReplace: ID; with: ID },
  ): Effect.Effect<void, NodeNotInTreeError | NodeHasNoParentError> =>
    storeUpdate(setTree, (tree) =>
      Effect.gen(function* () {
        const toReplacePanel = yield* Node.getOrError(tree, { id: toReplace });
        const replacementPanel = yield* Node.getOrError(tree, {
          id: replacement,
        });

        if (Option.isNone(toReplacePanel.parent))
          return new NodeHasNoParentError({ id: toReplace });

        const toReplacePanelParentId = toReplacePanel.parent.value;
        const toReplacePanelParent = yield* Node.Parent.getOrError(tree, {
          parentId: toReplacePanelParentId,
        });

        // remove replacement from parent
        if (Option.isSome(replacementPanel.parent)) {
          const replacementPanelParentId = replacementPanel.parent.value;
          const replacementPanelParent = yield* Node.Parent.getOrError(tree, {
            parentId: replacementPanelParentId,
          });

          replacementPanelParent.layout.children =
            replacementPanelParent.layout.children.filter(
              (childId) => childId.uuid !== replacement.uuid,
            );

          yield* Node.Parent.redistributeChildren(setTree, {
            parentId: replacementPanelParentId,
          });

          replacementPanel.parent = Option.none();
        }

        // remove old panel from it parent - inserting new
        const percentOfParent = toReplacePanel.percentOfParent;
        replacementPanel.percentOfParent = percentOfParent;
        toReplacePanel.percentOfParent = Percent(1);

        toReplacePanelParent.layout.children.splice(
          toReplacePanelParent.layout.children.findIndex(
            (childId) => childId.uuid === toReplace.uuid,
          ),
          1,
          replacementPanel.id,
        );

        toReplacePanel.parent = Option.none();
        replacementPanel.parent = Option.some(toReplacePanelParentId);

        return Effect.succeed(void {});
      }),
    );

  // export const swapWith = (
  //   setTree: SetTree,
  //   { oldId: swapOut, newId: swapIn }: { oldId: ID; newId: ID },
  // ): Effect.Effect<void, NodeNotInTreeError> =>
  //   storeUpdate(setTree, (tree) =>
  //     Effect.gen(function* () {
  //       const outPanel = yield* Node.getOrError(tree, { id: swapOut });
  //       const inPanel = yield* Node.getOrError(tree, { id: swapIn });

  //       if (Option.isNone(outPanel.parent))
  //         return new NodeHasNoParentError({ id: swapOut });

  //       const outParentPanelId = outPanel.parent.value;
  //       const outPanelParentPanel = yield* Node.Parent.getOrError(tree, {
  //         parentId: outParentPanelId,
  //       });

  //       // remove the to swap in panel from its parent
  //       if (Option.isSome(inPanel.parent)) {
  //         const inPanelParentId = inPanel.parent.value;
  //         const inPanelParentPanel = yield* Node.Parent.getOrError(tree, {
  //           parentId: inPanelParentId,
  //         });

  //         inPanelParentPanel.layout.children =
  //           inPanelParentPanel.layout.children.filter((id) => id !== swapIn);

  //         yield* Node.Parent.redistributeChildren(setTree, {
  //           parentId: inPanelParentId,
  //         });
  //       }

  //       // TODO: unfinished
  //     }),
  //   );

  export const promoteToParent = (
    setTree: SetTree,
    { id, layout }: { id: ID; layout: Layout },
  ): Effect.Effect<ID.Parent, NodeNotInTreeError | NodeHasNoParentError> =>
    Effect.gen(function* () {
      const newParentId = yield* Node.Parent.create(setTree, {
        layout: layout,
      });

      yield* Node.replaceWith(setTree, {
        toReplace: id,
        with: newParentId,
      });

      yield* Node.Parent.addChild(setTree, {
        parentId: newParentId,
        childId: id,
      }).pipe(
        Effect.catchTag("NodeAlreadyHasParentError", () =>
          Effect.dieMessage(
            "unreachable: promoted panel should not have a parent since Node.replaceWith should have removed it",
          ),
        ),
      );

      return newParentId;
    });

  export namespace Parent {
    export const init = (props: Node.ParentProps) =>
      Effect.sync<Parent>(() => ({
        _tag: "parent",
        ...Data.ParentProps(),
        ...props,
      }));

    export function create(
      setTree: SetTree,
      props: Omit<Node.ParentProps, "id">,
    ): Effect.Effect<ID.Parent>;

    export function create(
      setTree: SetTree,
      props: Omit<Node.ParentProps, "id">,
      { addTo }: { addTo: ID.Parent },
    ): Effect.Effect<ID.Parent, NodeNotInTreeError | NodeAlreadyHasParentError>;

    export function create(
      setTree: SetTree,
      props: Omit<Node.ParentProps, "id">,
      { addTo }: { addTo?: ID.Parent } = {},
    ): Effect.Effect<
      ID.Parent,
      NodeNotInTreeError | NodeAlreadyHasParentError
    > {
      return storeUpdate(setTree, (tree) =>
        Effect.gen(function* () {
          const id = yield* ID.create.Parent;

          const parent = yield* init({ id, ...props });
          tree.nodes[id.uuid] = parent;

          if (addTo)
            yield* Node.Parent.addChild(setTree, {
              parentId: addTo,
              childId: id,
            });

          return id;
        }),
      );
    }

    export const get = (
      tree: Tree,
      { parentId: id }: { parentId: ID.Parent },
    ): Option.Option<Node.Parent> =>
      Option.flatMap(Node.get(tree, { id }), Node.$as("parent"));

    export const getOrError = (
      tree: Tree,
      {
        parentId: id,
        gettingParentId,
      }: { parentId: ID.Parent; gettingParentId?: ID.Parent },
    ): Effect.Effect<Node.Parent, NodeNotInTreeError> =>
      Effect.gen(function* () {
        const node = yield* Node.getOrError(tree, {
          id,
          gettingParentId,
        });
        return yield* Effect.succeed(
          Option.getOrThrow(Node.$as("parent")(node)),
        );
      });

    export const update = (
      setTree: SetTree,
      { id, props }: { id: ID.Parent; props: Partial<Omit<Data.Parent, "id">> },
    ): Effect.Effect<void, NodeNotInTreeError> =>
      storeUpdate(setTree, (tree) =>
        Effect.gen(function* () {
          // debugger;
          const node = yield* Node.Parent.getOrError(tree, { parentId: id });
          tree.nodes[id.uuid] = { ...node, ...props };
          yield* Effect.succeed(void {});
        }),
      );

    export const addChild = (
      setTree: SetTree,
      { parentId, childId: newChildId }: { parentId: ID.Parent; childId: ID },
    ): Effect.Effect<void, NodeNotInTreeError | NodeAlreadyHasParentError> =>
      storeUpdate(setTree, (tree) =>
        Effect.gen(function* () {
          // This keep the ratio of sizes of existing panels while adding
          // a new one still trying to honor its percent

          const parent = yield* Node.Parent.getOrError(tree, {
            parentId: parentId,
          });
          const newChild = yield* Node.getOrError(tree, { id: newChildId });

          if (ID.$is("parent")(newChildId) && Layout.$is("tabs")(parent.layout))
            return Effect.fail(
              new CannotAddParentToTabsLayout({
                addingTo: parentId,
                child: newChildId,
              }),
            );

          if (Option.isSome(newChild.parent))
            return Effect.fail(
              new NodeAlreadyHasParentError({ id: newChildId }),
            );

          const n = parent.layout.children.length;
          newChild.parent = Option.some(parentId);

          let sum = 0;
          for (const childId of parent.layout.children) {
            const child = yield* Node.getOrError(tree, {
              id: childId,
              gettingParentId: parentId,
            });
            sum += child.percentOfParent;
          }

          const pNew = pipe(
            newChild.percentOfParent / (n + 1),
            Order.clamp(Order.number)({ minimum: 0, maximum: 1 }),
          );

          const pushChild = () => {
            if (ID.$is("parent")(newChildId)) {
              tsafe.assert(!tsafe.is<Layout.Tabs>(parent.layout));
              parent.layout.children.push(newChildId);
            } else {
              parent.layout.children.push(newChildId);
            }
          };

          if (sum <= 0) {
            if (n === 0) {
              newChild.percentOfParent = Percent(1);

              pushChild();

              return Effect.succeed(void {});
            }

            const each = (1 - pNew) / n;

            for (const childId of parent.layout.children) {
              const child = yield* Node.getOrError(tree, {
                id: childId,
                gettingParentId: parentId,
              });
              child.percentOfParent = Percent(each);
            }

            newChild.percentOfParent = Percent(pNew);
            pushChild();

            return Effect.succeed(void {});
          }

          const scale = (1 - pNew) / sum;

          for (const childId of parent.layout.children) {
            const child = yield* Node.getOrError(tree, {
              id: childId,
              gettingParentId: parentId,
            });
            child.percentOfParent = Percent(child.percentOfParent * scale);
          }

          newChild.percentOfParent = Percent(pNew);
          pushChild();

          return Effect.succeed(void {});
        }),
      );

    export const redistributeChildren = (
      setTree: SetTree,
      { parentId, exclude = [] }: { parentId: ID.Parent; exclude?: ID[] },
    ): Effect.Effect<void, NodeNotInTreeError> =>
      storeUpdate(setTree, (tree) =>
        Effect.gen(function* () {
          const parent = yield* Node.Parent.getOrError(tree, {
            parentId: parentId,
          });

          const n = parent.layout.children.length;
          if (n === 0) return Effect.void;

          const children = yield* Effect.forEach(
            parent.layout.children,
            (childId) =>
              Node.getOrError(tree, {
                id: childId,
                gettingParentId: parent.id,
              }),
          );

          // Partition into fixed and adjustable
          const excludeUuids = exclude.map((id) => id.uuid);
          const fixed = children.filter((c) =>
            excludeUuids.includes(c.id.uuid),
          );
          const adjustable = children.filter(
            (c) => !excludeUuids.includes(c.id.uuid),
          );

          const fixedSum = fixed.reduce((acc, c) => acc + c.percentOfParent, 0);
          const adjustableSum = adjustable.reduce(
            (acc, c) => acc + c.percentOfParent,
            0,
          );

          const remaining = 1 - fixedSum;

          if (adjustable.length === 0) {
            // nothing to redistribute
            return Effect.void;
          }

          if (adjustableSum <= 0) {
            // fallback: divide evenly among adjustables
            const each = remaining / adjustable.length;
            for (const c of adjustable) {
              c.percentOfParent = Percent(each);
            }
          } else {
            // scale proportionally to fit remaining space
            const scale = remaining / adjustableSum;
            for (const c of adjustable) {
              c.percentOfParent = Percent(c.percentOfParent * scale);
            }
          }

          return Effect.void;
        }),
      );
  }

  export namespace Leaf {
    export const init = (props: LeafProps) =>
      Effect.sync<Leaf>(() => ({
        _tag: "leaf",
        ...Data.LeafProps(),
        ...props,
      }));

    export function create(
      setTree: SetTree,
      props: Omit<Node.LeafProps, "id">,
    ): Effect.Effect<ID.Leaf>;

    export function create(
      setTree: SetTree,
      props: Omit<Node.LeafProps, "id">,
      { addTo }: { addTo: ID.Parent },
    ): Effect.Effect<ID.Leaf, NodeNotInTreeError | NodeAlreadyHasParentError>;

    export function create(
      setTree: SetTree,
      props: Omit<Node.LeafProps, "id">,
      { addTo }: { addTo?: ID.Parent } = {},
    ): Effect.Effect<ID.Leaf, NodeNotInTreeError | NodeAlreadyHasParentError> {
      return storeUpdate(setTree, (tree) =>
        Effect.gen(function* () {
          const id = yield* ID.create.Leaf;

          const leaf = yield* init({ id, ...props });
          tree.nodes[id.uuid] = leaf;

          if (addTo)
            yield* Node.Parent.addChild(setTree, {
              parentId: addTo,
              childId: id,
            });

          return id;
        }),
      );
    }

    export const get = (
      tree: Tree,
      { id }: { id: ID.Leaf },
    ): Option.Option<Node.Leaf> =>
      Option.flatMap(Node.get(tree, { id }), Node.$as("leaf"));

    export const getOrError = (
      tree: Tree,
      { id, parentId }: { id: ID.Leaf; parentId?: ID.Parent },
    ): Effect.Effect<Node.Leaf, NodeNotInTreeError> =>
      Effect.gen(function* () {
        const node = yield* Node.getOrError(tree, {
          id,
          gettingParentId: parentId,
        });
        return Option.getOrThrow(Node.$as("leaf")(node));
      });

    export const update = (
      setTree: SetTree,
      { id, props }: { id: ID.Leaf; props: Partial<Omit<Data.Leaf, "id">> },
    ): Effect.Effect<void, NodeNotInTreeError> =>
      storeUpdate(setTree, (tree) =>
        Effect.gen(function* () {
          const node = yield* Node.Leaf.getOrError(tree, { id });
          tree.nodes[id.uuid] = { ...node, ...props };
          yield* Effect.succeed(void {});
        }),
      );
  }

  export const destroy = (
    setTree: SetTree,
    {
      id,
      removeFromParent = true,
    }: {
      id: ID;
      removeFromParent?: boolean;
    },
  ): Effect.Effect<void, NodeNotInTreeError | CannotDeleteRootError> =>
    storeUpdate(setTree, (tree) =>
      Effect.gen(function* () {
        if (id === tree.root) return Effect.fail(new CannotDeleteRootError());

        const node = yield* Node.getOrError(tree, { id });
        const parentId = Option.getOrUndefined(node.parent);

        if (removeFromParent && parentId) {
          const parent = yield* Node.Parent.getOrError(tree, {
            parentId: parentId,
          });
          parent.layout.children = parent.layout.children.filter(
            (childId) => childId.uuid !== id.uuid,
          );
          node.parent = Option.none();
          yield* Node.Parent.redistributeChildren(setTree, { parentId });
        }

        if (Node.$is("parent")(node)) {
          yield* Effect.forEach(node.layout.children, (childId) =>
            pipe(
              Option.isSome(Node.get(tree, { id: childId })),
              Effect.succeed,
              Effect.map((exists) => ({ childId, exists })),
              Effect.andThen(({ childId, exists }) =>
                Effect.if(!exists, {
                  onTrue: () =>
                    Effect.fail(
                      new NodeNotInTreeError({ id: childId }).withParent(
                        node.id,
                      ),
                    ),
                  onFalse: () => Effect.void,
                }),
              ),
            ),
          );

          for (const childId of node.layout.children) {
            yield* destroy(setTree, {
              id: childId,
              removeFromParent: false,
            }).pipe(
              Effect.matchEffect({
                onFailure: (error) =>
                  Match.value(error).pipe(
                    // Something is very wrong if we hit this error
                    Match.tag("CannotDeleteRootError", (error) =>
                      Effect.fail(error),
                    ),
                    // we should't be able to hit this error
                    Match.tag("NodeNotInTreeError", (error) =>
                      Effect.failCause(
                        Cause.die({
                          message:
                            "unreachable: Child panel does not exist, even though we just checked",
                          error,
                        }),
                      ),
                    ),
                    Match.exhaustive,
                  ),
                onSuccess: () => Effect.succeed(void {}),
              }),
            );
          }
        }

        delete tree.nodes[id.uuid];

        return Effect.succeed(void {});
      }),
    );

  /** @deprecated */
  export const setPercentOfParent = (
    setTree: SetTree,
    { id, percent }: { id: ID; percent: Percent },
  ): Effect.Effect<void, NodeNotInTreeError> =>
    storeUpdate(setTree, (tree) =>
      Effect.gen(function* () {
        const node = yield* Node.getOrError(tree, { id });

        node.percentOfParent = percent;

        if (Option.isSome(node.parent)) {
          const parentId = Option.getOrThrow(node.parent);
          yield* Node.Parent.redistributeChildren(setTree, {
            parentId,
            exclude: [id],
          });
        }
      }),
    );
}
export type Node = Node.TaggedMap[Node.Tag];

export type Tree = {
  root: ID.Parent;
  nodes: Record<ID.IDBase, Node>;
};
export type SetTree = SetStoreFunction<Tree>;

export namespace Tree {
  export const create = ({
    titlebar,
  }: {
    titlebar?: Component;
  }): Effect.Effect<Tree> =>
    Effect.andThen(ID.create.Parent, (id) => ({
      root: id,
      nodes: {
        [id.uuid]: Node.Parent.init({
          id,
          titlebar: Option.fromNullable(titlebar),
          edgeDropConfig: {
            left: true,
            right: true,
            top: false,
            bottom: false,
          },
        }).pipe(Effect.runSync),
      },
    }));
}

export class NodeNotInTreeError extends Data.TaggedError("NodeNotInTreeError")<{
  id: ID;
}> {
  public readonly parentList: ID.Parent[] = [];

  withParent = (id: ID.Parent): NodeNotInTreeError => {
    this.parentList.push(id);
    return this;
  };

  get message(): string {
    return (
      `Node with id: '${this.id.uuid}' does not exist; ` +
      `parent chain: ${JSON.stringify(this.parentList.map(({ uuid }) => uuid))}`
    );
  }
}
export class NodeAlreadyHasParentError extends Data.TaggedError(
  "NodeAlreadyHasParentError",
)<{
  id: ID;
}> {
  message: string = `Node (${this.id.uuid}) already has a parent`;
}

export class NodeHasNoParentError extends Data.TaggedError(
  "NodeHasNoParentError",
)<{
  id: ID;
}> {
  message: string = `Node (${this.id.uuid}) has no parent`;
}

export class CannotDeleteRootError extends Data.TaggedError(
  "CannotDeleteRootError",
)<{}> {
  message: string = "Cannot delete root panel";
}

export class CannotAddParentToTabsLayout extends Data.TaggedError(
  "CannotAddParentToTabsLayout",
)<{
  addingTo: ID.Parent;
  child: ID.Parent;
}> {
  message: string = `Cannot add child (with id '${this.child.uuid}') which is a parent to a parent (with id '${this.addingTo.uuid}') which has a tabs layout`;
}
