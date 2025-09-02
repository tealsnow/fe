import * as uuid from "uuid";
import { Brand, Cause, Data, Effect, Match, Option, Order, pipe } from "effect";
import { SetStoreFunction } from "solid-js/store";

import { storeUpdate } from "~/lib/SignalObject";

export type ID = string & Brand.Brand<"PanelId">;
export const ID = Brand.refined<ID>(
  (s) => uuid.validate(s),
  (s) => Brand.error(`Expected ${s} to be a valid UUID`),
);

export type Percent = number & Brand.Brand<"Percent">;
export const Percent = Brand.refined<Percent>(
  (n) => Number.isFinite(n) && n >= 0 && n <= 1,
  (n) => Brand.error(`Expected ${n} to be a percentage`),
);

export type Layout = "vertical" | "horizontal";

export type NodePropsRequired = {
  dbgName: string;
};

export type NodePropsOptional = {
  layout: Layout;
  percentOfParent: Percent;

  tabs: Tab[];
};

export const NodePropsOptional: NodePropsOptional = {
  layout: "horizontal",
  percentOfParent: Percent(1),

  tabs: [],
};

export type NodePropsOptionalPartial = Partial<NodePropsOptional>;

export type NodeProps = NodePropsRequired & NodePropsOptionalPartial;

export type NodePropsCommon = NodePropsRequired & NodePropsOptional;

export type PanelNodePropsCommonPartial = Partial<NodePropsCommon>;

export type Node = NodePropsCommon & {
  id: ID;
  parent: Option.Option<ID>;

  children: ID[];
  tabs: Tab[];
};

export type Tab = {
  title: string;
};

export type Tree = {
  root: ID;
  nodes: Record<ID, Node>;
};

export type SetTree = SetStoreFunction<Tree>;

export class PanelDoesNotExistError extends Data.TaggedError(
  "PanelDoesNotExistError",
)<{}> {
  public readonly parentList: ID[] = [];

  constructor(public readonly id: ID) {
    super();
  }

  withParent = (id: ID): PanelDoesNotExistError => {
    this.parentList.push(id);
    return this;
  };

  get message(): string {
    return (
      `Panel with id: '${this.id}' does not exist; ` +
      `parent chain: ${JSON.stringify(this.parentList)}`
    );
  }
}

export class CannotDeleteRootPanelError extends Data.TaggedError(
  "CannotDeleteRootPanelError",
)<{}> {
  message: string = "Cannot delete root panel";
}

export class AlreadyHasParentError extends Data.TaggedError(
  "AlreadyHasParentError",
)<{}> {
  constructor(public readonly id: ID) {
    super();
  }

  message: string = `Panel (${this.id}) already has a parent`;
}

export const createId: Effect.Effect<ID, never> = Effect.sync(() =>
  ID(uuid.v4()),
);

export const createTree: Effect.Effect<Tree, never> = Effect.andThen(
  createId,
  (root) =>
    ({
      root,
      nodes: {
        [root]: {
          dbgName: "root",
          parent: Option.none(),
          id: root,
          children: [],
          ...NodePropsOptional,
        },
      },
    }) satisfies Tree,
);

export const createNode = (
  setTree: SetTree,
  props: NodeProps,
  { newId }: { newId?: ID } = {},
): Effect.Effect<ID, never> =>
  storeUpdate(setTree, (tree) =>
    Effect.gen(function* () {
      const id = newId ?? (yield* createId);
      const node: Node = {
        id,
        parent: Option.none(),
        children: [],
        ...{ ...NodePropsOptional, ...props },
      };

      tree.nodes[id] = node;

      return id;
    }),
  );

export const nodeExists = (
  tree: Tree,
  { id }: { id: ID },
): Effect.Effect<boolean, never> =>
  Effect.gen(function* () {
    const node = tree.nodes[id];
    return node !== undefined;
  });

export const getNode = (
  tree: Tree,
  params: {
    id: ID;
    parentId?: ID;
  },
): Effect.Effect<Node, PanelDoesNotExistError> => {
  const node = tree.nodes[params.id];
  if (!node)
    return Effect.fail(new PanelDoesNotExistError(params.id)).pipe(
      Effect.mapError((err) =>
        Match.value(err).pipe(
          Match.tag("PanelDoesNotExistError", (err) =>
            params.parentId ? err.withParent(params.parentId) : err,
          ),
          Match.exhaustive,
        ),
      ),
    );
  return Effect.succeed(node);
};

export const addChild = (
  setTree: SetTree,
  {
    parentId,
    newChildId,
  }: {
    parentId: ID;
    newChildId: ID;
  },
): Effect.Effect<void, PanelDoesNotExistError | AlreadyHasParentError> =>
  storeUpdate(setTree, (tree) =>
    Effect.gen(function* () {
      // This keep the ratio of sizes of existing panels while adding
      // a new one still trying to honor its percent

      const parent = yield* getNode(tree, { id: parentId });
      const newChild = yield* getNode(tree, { id: newChildId });

      if (Option.isSome(newChild.parent))
        yield* Effect.fail(new AlreadyHasParentError(newChildId));

      const n = parent.children.length;
      newChild.parent = Option.some(parentId);

      let sum = 0;
      for (const childId of parent.children) {
        const child = yield* getNode(tree, {
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
          return Effect.void;
        }

        const each = (1 - pNew) / n;

        for (const childId of parent.children) {
          const child = yield* getNode(tree, {
            id: childId,
            parentId,
          });
          child.percentOfParent = Percent(each);
        }

        newChild.percentOfParent = Percent(pNew);
        parent.children.push(newChildId);

        return Effect.void;
      }

      const scale = (1 - pNew) / sum;

      for (const childId of parent.children) {
        const child = yield* getNode(tree, {
          id: childId,
          parentId,
        });
        child.percentOfParent = Percent(child.percentOfParent * scale);
      }

      newChild.percentOfParent = Percent(pNew);
      parent.children.push(newChildId);
    }),
  );

export const redistributeChildren = (
  setTree: SetTree,
  { id, exclude = [] }: { id: ID; exclude?: ID[] },
): Effect.Effect<void, PanelDoesNotExistError> =>
  storeUpdate(setTree, (tree) =>
    Effect.gen(function* () {
      const parent = yield* getNode(tree, { id });

      const n = parent.children.length;
      if (n === 0) return Effect.void;

      // Collect children
      const children: Node[] = [];
      for (const childId of parent.children) {
        const child = yield* getNode(tree, {
          id: childId,
          parentId: parent.id,
        });
        children.push(child);
      }

      // Partition into fixed and adjustable
      const fixed = children.filter((c) => exclude.includes(c.id));
      const adjustable = children.filter((c) => !exclude.includes(c.id));

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
    }),
  );

export const uniformChildren = (
  setTree: SetTree,
  { id }: { id: ID },
): Effect.Effect<void, PanelDoesNotExistError> =>
  storeUpdate(setTree, (tree) =>
    Effect.gen(function* () {
      const parent = yield* getNode(tree, { id });

      const n = parent.children.length;
      if (n === 0) return Effect.void;

      const each = 1 / n;

      for (const childId of parent.children) {
        const child = yield* getNode(tree, {
          id: childId,
          parentId: parent.id,
        });
        child.percentOfParent = Percent(each);
      }
    }),
  );

export const deleteNode = (
  setTree: SetTree,
  {
    id,
    removeFromParent = true,
  }: {
    id: ID;
    removeFromParent?: boolean;
  },
): Effect.Effect<void, PanelDoesNotExistError | CannotDeleteRootPanelError> =>
  storeUpdate(setTree, (tree) =>
    Effect.gen(function* () {
      if (id === tree.root)
        yield* Effect.fail(new CannotDeleteRootPanelError());

      const node = yield* getNode(tree, { id });

      const parentId = Option.getOrUndefined(node.parent);
      if (removeFromParent && parentId) {
        const parent = yield* getNode(tree, { id: parentId });
        parent.children = parent.children.filter((childId) => childId !== id);
        node.parent = Option.none();

        yield* redistributeChildren(setTree, { id: parentId });
      }

      yield* Effect.forEach(node.children, (childId) =>
        nodeExists(tree, { id: childId }).pipe(
          Effect.map((exists) => ({ childId, exists })),
          Effect.andThen(({ childId, exists }) =>
            Effect.if(!exists, {
              onTrue: () =>
                Effect.fail(new PanelDoesNotExistError(childId).withParent(id)),
              onFalse: () => Effect.void,
            }),
          ),
        ),
      );

      for (const childId of node.children) {
        yield* deleteNode(setTree, {
          id: childId,
          removeFromParent: false,
        }).pipe(
          Effect.matchEffect({
            onFailure: (error) =>
              Match.value(error).pipe(
                // Something is very wrong if we hit this error
                Match.tag("CannotDeleteRootPanelError", (error) =>
                  Effect.fail(error),
                ),
                // we should't be able to hit this error
                Match.tag("PanelDoesNotExistError", (error) =>
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

      delete tree.nodes[id];

      yield* Effect.succeed(void {});
    }),
  );

export const validateChildrenSizes = (
  tree: Tree,
  { id }: { id: ID },
): Effect.Effect<{ ok: boolean; difference: number }, PanelDoesNotExistError> =>
  Effect.gen(function* () {
    const node = yield* getNode(tree, { id });

    if (node.children.length === 0) return { ok: true, difference: 0 };

    let sum = 0;
    for (const childId of node.children) {
      const child = yield* getNode(tree, {
        id: childId,
        parentId: id,
      });
      sum += child.percentOfParent;
    }

    const approxEqual = (a: number, b: number, tolerance: number) => {
      return Math.abs(a - b) < tolerance;
    };

    // @NOTE: The tolerance here is tenuous at best,
    //   I have only seen a difference of 1.11022e-16 so far - so hopefully
    //   this is enough for our use case, there shouldn't be so many children
    //   of a single panel for the calculations to drift too far
    const ok = approxEqual(sum, 1, 2 * Number.EPSILON);

    return {
      ok,
      difference: sum - 1,
    };
  });

export const updateNode = (
  setTree: SetTree,
  { id, props }: { id: ID; props: PanelNodePropsCommonPartial },
): Effect.Effect<void, PanelDoesNotExistError> =>
  storeUpdate(setTree, (tree) =>
    Effect.gen(function* () {
      const node = yield* getNode(tree, { id });

      tree.nodes[id] = {
        ...node,
        ...props,
      };

      yield* Effect.succeed(void {});
    }),
  );
