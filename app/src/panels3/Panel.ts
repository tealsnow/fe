import * as uuid from "uuid";
import { Brand, Cause, Data, Effect, Match, Option, Order, pipe } from "effect";
import { storeUpdate } from "../SignalObject";
import { SetStoreFunction } from "solid-js/store";

export type PanelId = string & Brand.Brand<"PanelId">;
export const PanelId = Brand.refined<PanelId>(
  (s) => uuid.validate(s),
  (s) => Brand.error(`Expected ${s} to be a valid UUID`),
);

export type Percent = number & Brand.Brand<"Percent">;
export const Percent = Brand.refined<Percent>(
  (n) => Number.isFinite(n) && n >= 0 && n <= 1,
  (n) => Brand.error(`Expected ${n} to be a percentage`),
);

export type PanelLayout = "vertical" | "horizontal";

export type PanelNodePropsRequired = {
  dbgName: string;
};

export type PanelNodePropsOptional = {
  layout: PanelLayout;
  percentOfParent: Percent;
};

export const PanelNodePropsOptional: PanelNodePropsOptional = {
  layout: "horizontal",
  percentOfParent: Percent(1),
};

export type PanelNodePropsOptionalPartial = Partial<PanelNodePropsOptional>;

export type PanelNodeProps = PanelNodePropsRequired &
  PanelNodePropsOptionalPartial;

export type PanelNodePropsCommon = PanelNodePropsRequired &
  PanelNodePropsOptional;

export type PanelNodePropsCommonPartial = Partial<PanelNodePropsCommon>;

export type PanelNode = PanelNodePropsCommon & {
  id: PanelId;
  parent: Option.Option<PanelId>;

  children: PanelId[];
};

export type PanelTree = {
  root: PanelId;
  nodes: Record<PanelId, PanelNode>;
};

export type SetPanelTree = SetStoreFunction<PanelTree>;

export class PanelDoesNotExistError extends Data.TaggedError(
  "PanelDoesNotExistError",
)<{}> {
  public readonly parentList: PanelId[] = [];

  constructor(public readonly id: PanelId) {
    super();
  }

  withParent = (id: PanelId): PanelDoesNotExistError => {
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
  constructor(public readonly id: PanelId) {
    super();
  }

  message: string = `Panel (${this.id}) already has a parent`;
}

export const createId: Effect.Effect<PanelId, never> = Effect.sync(() =>
  PanelId(uuid.v4()),
);

export const createTree: Effect.Effect<PanelTree, never> = Effect.andThen(
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
          ...PanelNodePropsOptional,
        },
      },
    }) satisfies PanelTree,
);

export const createPanel = (
  setTree: SetPanelTree,
  props: PanelNodeProps,
  newId?: PanelId,
): Effect.Effect<PanelId, never> =>
  storeUpdate(setTree, (tree) =>
    Effect.gen(function* (_) {
      const id = newId ?? (yield* createId);
      const panel: PanelNode = {
        id,
        parent: Option.none(),
        children: [],
        ...{ ...PanelNodePropsOptional, ...props },
      };

      tree.nodes[id] = panel;

      return id;
    }),
  );

export const doesPanelExist = (
  tree: PanelTree,
  {
    panelId,
  }: {
    panelId: PanelId;
  },
): Effect.Effect<boolean, never> =>
  Effect.gen(function* () {
    const panel = tree.nodes[panelId];
    return panel !== undefined;
  });

export const getPanel = (
  tree: PanelTree,
  params: {
    panelId: PanelId;
    parentId?: PanelId;
  },
): Effect.Effect<PanelNode, PanelDoesNotExistError> => {
  const panel = tree.nodes[params.panelId];
  if (!panel)
    return Effect.fail(new PanelDoesNotExistError(params.panelId)).pipe(
      Effect.mapError((err) =>
        Match.value(err).pipe(
          Match.tag("PanelDoesNotExistError", (err) =>
            params.parentId ? err.withParent(params.parentId) : err,
          ),
          Match.exhaustive,
        ),
      ),
    );
  return Effect.succeed(panel);
};

export const addChild = (
  setTree: SetPanelTree,
  {
    parentId,
    newChildId,
  }: {
    parentId: PanelId;
    newChildId: PanelId;
  },
): Effect.Effect<void, PanelDoesNotExistError | AlreadyHasParentError> =>
  storeUpdate(setTree, (tree) =>
    Effect.gen(function* () {
      // This keep the ratio of sizes of existing panels while adding
      // a new one still trying to honor its percent

      const parent = yield* getPanel(tree, { panelId: parentId });
      const newChild = yield* getPanel(tree, { panelId: newChildId });

      if (Option.isSome(newChild.parent))
        yield* Effect.fail(new AlreadyHasParentError(newChildId));

      const n = parent.children.length;
      newChild.parent = Option.some(parentId);

      let sum = 0;
      for (const childId of parent.children) {
        const child = yield* getPanel(tree, {
          panelId: childId,
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
          const child = yield* getPanel(tree, {
            panelId: childId,
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
        const child = yield* getPanel(tree, {
          panelId: childId,
          parentId,
        });
        child.percentOfParent = Percent(child.percentOfParent * scale);
      }

      newChild.percentOfParent = Percent(pNew);
      parent.children.push(newChildId);
    }),
  );

export const deletePanel = (
  setTree: SetPanelTree,
  {
    panelId,
    removeFromParent = true,
  }: {
    panelId: PanelId;
    removeFromParent?: boolean;
  },
): Effect.Effect<void, PanelDoesNotExistError | CannotDeleteRootPanelError> =>
  storeUpdate(setTree, (tree) =>
    Effect.gen(function* () {
      if (panelId === tree.root)
        yield* Effect.fail(new CannotDeleteRootPanelError());

      const panel = yield* getPanel(tree, { panelId });

      const parentId = Option.getOrUndefined(panel.parent);
      if (removeFromParent && parentId) {
        const parent = yield* getPanel(tree, { panelId: parentId });
        const idx = parent.children.findIndex((id) => id === panelId);
        parent.children.splice(idx, 1);
        panel.parent = Option.none();
      }

      yield* Effect.forEach(panel.children, (childId) =>
        doesPanelExist(tree, { panelId: childId }).pipe(
          Effect.map((exists) => ({ childId, exists })),
          Effect.andThen(({ childId, exists }) =>
            Effect.if(!exists, {
              onTrue: () =>
                Effect.fail(
                  new PanelDoesNotExistError(childId).withParent(panelId),
                ),
              onFalse: () => Effect.void,
            }),
          ),
        ),
      );

      for (const childId of panel.children) {
        yield* deletePanel(setTree, {
          panelId: childId,
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

      delete tree.nodes[panelId];

      yield* Effect.succeed(void {});
    }),
  );

export const validateChildrenSizes = (
  tree: PanelTree,
  { panelId }: { panelId: PanelId },
): Effect.Effect<{ ok: boolean; difference: number }, PanelDoesNotExistError> =>
  Effect.gen(function* () {
    const panel = yield* getPanel(tree, { panelId });

    if (panel.children.length === 0) return { ok: true, difference: 0 };

    let sum = 0;
    for (const childId of panel.children) {
      const child = yield* getPanel(tree, {
        panelId: childId,
        parentId: panelId,
      });
      sum += child.percentOfParent;
    }

    return { ok: sum === 1, difference: Math.abs(sum - 1) };
  });

export const update = (
  setTree: SetPanelTree,
  { panelId, props }: { panelId: PanelId; props: PanelNodePropsCommonPartial },
): Effect.Effect<void, PanelDoesNotExistError> =>
  storeUpdate(setTree, (tree) =>
    Effect.gen(function* () {
      const panel = yield* getPanel(tree, { panelId });

      tree.nodes[panelId] = {
        ...panel,
        ...props,
      };

      yield* Effect.succeed(void {});
    }),
  );
