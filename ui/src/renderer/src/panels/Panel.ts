import * as uuid from "uuid";
import { Brand, Cause, Data, Effect, Match, Option, Order, pipe } from "effect";
import { JSX } from "solid-js";
import * as tsafe from "tsafe";

import { SetStoreFunction } from "solid-js/store";
import { PickOptional } from "~/lib/type_helpers";
import { EmptyJsx } from "~/lib/emptyJsx";
import { storeUpdate } from "~/lib/SignalObject";

export namespace ID {
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

export type Layout = "vertical" | "horizontal" | "tabs";

export namespace Node {
  export namespace Data {
    export type Common = {
      id: ID;
      parent?: Option.Option<ID.Parent>;
      percentOfParent?: Percent;
    };
    export const Common = (): Required<PickOptional<Common>> =>
      ({
        parent: Option.none(),
        percentOfParent: Percent(1),
      }) as const;

    export type ParentProps = Common & {
      id: ID.Parent;
      layout?: Layout;
      active?: Option.Option<ID>;
      children?: ID[];
    };
    export const ParentProps = (): Required<PickOptional<ParentProps>> =>
      ({
        layout: "horizontal",
        active: Option.none(),
        children: [],
        ...Common(),
      }) as const;
    export type Parent = Required<ParentProps>;

    export type LeafProps = Common & {
      id: ID.Leaf;
      title: string;
      content?: () => JSX.Element;
    };
    export const LeafProps = (): Required<PickOptional<LeafProps>> =>
      ({
        content: EmptyJsx,
        ...Common(),
      }) as const;
    export type Leaf = Required<LeafProps>;
  }

  export type Map = {
    parent: Data.Parent;
    leaf: Data.Leaf;
  };
  export type Tag = keyof Map;
  // eslint-disable-next-line @typescript-eslint/no-unused-expressions
  tsafe.assert<tsafe.Equals<Tag, ID.Tag>>;

  export type TaggedMap = {
    [K in keyof Map]: { readonly _tag: K } & Map[K];
  };

  export type Of<K extends Tag> = TaggedMap[K];

  export type Parent = Of<"parent">;
  export type Leaf = Of<"leaf">;
  // eslint-disable-next-line @typescript-eslint/no-unused-expressions
  tsafe.assert<tsafe.Extends<Parent, Node>>;
  // eslint-disable-next-line @typescript-eslint/no-unused-expressions
  tsafe.assert<tsafe.Extends<Leaf, Node>>;

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
    { id, parentId }: { id: ID; parentId?: ID.Parent },
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

  export namespace Parent {
    export const init = (props: Node.ParentProps) =>
      Effect.sync<Parent>(() => ({
        _tag: "parent",
        ...Data.ParentProps(),
        ...props,
      }));

    export const create = (
      setTree: SetTree,
      props: Omit<Node.ParentProps, "id">,
    ): Effect.Effect<ID.Parent> =>
      storeUpdate(setTree, (tree) =>
        Effect.gen(function* () {
          const id = yield* ID.create.Parent;

          const parent = yield* init({ id, ...props });
          tree.nodes[id.uuid] = parent;

          return id;
        }),
      );

    export const get = (
      tree: Tree,
      { id }: { id: ID.Parent },
    ): Option.Option<Node.Parent> =>
      Option.flatMap(Node.get(tree, { id }), Node.$as("parent"));

    export const getOrError = (
      tree: Tree,
      { id, parentId }: { id: ID.Parent; parentId?: ID.Parent },
    ): Effect.Effect<Node.Parent, NodeNotInTreeError> =>
      Effect.gen(function* () {
        const node = yield* Node.getOrError(tree, { id, parentId });
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
          const node = yield* Node.Parent.getOrError(tree, { id });
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

          const parent = yield* Node.Parent.getOrError(tree, { id: parentId });
          const newChild = yield* Node.getOrError(tree, { id: newChildId });

          if (Option.isSome(newChild.parent))
            yield* Effect.fail(
              new NodeAlreadyHasParentError({ id: newChildId }),
            );

          const n = parent.children.length;
          newChild.parent = Option.some(parentId);

          let sum = 0;
          for (const childId of parent.children) {
            const child = yield* Node.getOrError(tree, {
              id: childId,
              parentId,
            });
            sum += child.percentOfParent;
          }

          const pNew = pipe(
            newChild.percentOfParent / (n + 1),
            Order.clamp(Order.number)({ minimum: 0, maximum: 1 }),
          );

          if (sum <= 0) {
            if (n === 0) {
              newChild.percentOfParent = Percent(1);
              parent.children.push(newChildId);
              // return Effect.void;
              return yield* Effect.succeed(void {});
            }

            const each = (1 - pNew) / n;

            for (const childId of parent.children) {
              const child = yield* Node.getOrError(tree, {
                id: childId,
                parentId,
              });
              child.percentOfParent = Percent(each);
            }

            newChild.percentOfParent = Percent(pNew);
            parent.children.push(newChildId);

            // return Effect.void;
            return yield* Effect.succeed(void {});
          }

          const scale = (1 - pNew) / sum;

          for (const childId of parent.children) {
            const child = yield* Node.getOrError(tree, {
              id: childId,
              parentId,
            });
            child.percentOfParent = Percent(child.percentOfParent * scale);
          }

          newChild.percentOfParent = Percent(pNew);
          parent.children.push(newChildId);

          return yield* Effect.succeed(void {});
        }),
      );

    export const redistributeChildren = (
      setTree: SetTree,
      { parentId, exclude = [] }: { parentId: ID.Parent; exclude?: ID[] },
    ): Effect.Effect<void, NodeNotInTreeError> =>
      storeUpdate(setTree, (tree) =>
        Effect.gen(function* () {
          const parent = yield* Node.Parent.getOrError(tree, { id: parentId });

          const n = parent.children.length;
          if (n === 0) return Effect.void;

          const children = yield* Effect.forEach(parent.children, (childId) =>
            Node.getOrError(tree, {
              id: childId,
              parentId: parent.id,
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

    export const create = (
      setTree: SetTree,
      props: Omit<Node.LeafProps, "id">,
    ): Effect.Effect<ID.Leaf> =>
      storeUpdate(setTree, (tree) =>
        Effect.gen(function* () {
          const id = yield* ID.create.Leaf;
          const leaf = yield* init({ id, ...props });
          tree.nodes[id.uuid] = leaf;
          return id;
        }),
      );

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
        const node = yield* Node.getOrError(tree, { id, parentId });
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
        if (id === tree.root) yield* Effect.fail(new CannotDeleteRootError());

        const node = yield* Node.getOrError(tree, { id });
        const parentId = Option.getOrUndefined(node.parent);

        if (removeFromParent && parentId) {
          const parent = yield* Node.Parent.getOrError(tree, { id: parentId });
          parent.children = parent.children.filter((childId) => childId !== id);
          node.parent = Option.none();
          yield* Node.Parent.redistributeChildren(setTree, { parentId });
        }

        if (Node.$is("parent")(node)) {
          yield* Effect.forEach(node.children, (childId) =>
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

          for (const childId of node.children) {
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

        yield* Effect.succeed(void {});
      }),
    );

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
  export const create: Effect.Effect<Tree, never> = Effect.andThen(
    ID.create.Parent,
    (id) => ({
      root: id,
      nodes: {
        [id.uuid]: Node.Parent.init({ id }).pipe(Effect.runSync),
      },
    }),
  );
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

export class CannotDeleteRootError extends Data.TaggedError(
  "CannotDeleteRootError",
)<{}> {
  message: string = "Cannot delete root panel";
}
