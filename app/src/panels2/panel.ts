import { Emitter } from "solid-events";
import { v4 as uuidv4 } from "uuid";
import { produceUpdate, StoreObjectProduce } from "~/lib/SignalObject";

import { Brand, Data, Effect, Match, Order } from "effect";

export type PanelId = string & Brand.Brand<"PanelId">;
export const PanelId = Brand.nominal<PanelId>();

const isPercent = (n: number): n is Percent =>
  Number.isFinite(n) && n >= 0 && n <= 1;

export type Percent = number & Brand.Brand<"Percent">;
export const Percent = Brand.refined<Percent>(
  (n) => isPercent(n),
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

export type PanelNode = PanelNodePropsCommon & {
  id: PanelId;
  parent?: PanelId;

  children: PanelId[];
};

export const NullPanelNode: PanelNode = {
  id: PanelId("__null"),
  dbgName: "null",
  layout: "horizontal",
  percentOfParent: Percent(1),
  parent: undefined,
  children: [],
};

export type PanelTreeData = Record<PanelId, PanelNode>;

export type PanelTreeStore = StoreObjectProduce<PanelTreeData>;

export class PanelDoesNotExistError extends Data.TaggedError(
  "PanelDoesNotExistError",
)<{}> {
  public readonly parentList: PanelId[] = [];

  constructor(public readonly id: PanelId) {
    super();
  }

  parent = (id: PanelId): PanelDoesNotExistError => {
    this.parentList.push(id);
    return this;
  };
}

export class CannotDeleteRootPanelError extends Data.TaggedError(
  "CannotDeleteRootPanelError",
)<{}> {}

export const panels = {
  newPanelId: (): PanelId => {
    return PanelId(uuidv4());
  },

  createRootPanelNode: (treeStore: PanelTreeStore): PanelId =>
    panels.newPanelNode(treeStore, { dbgName: "root" }, PanelId("__root")),

  newPanelNode: (
    treeStore: PanelTreeStore,
    props: PanelNodeProps,
    newId?: PanelId,
  ): PanelId =>
    produceUpdate(treeStore, (tree) => {
      const id = newId ?? panels.newPanelId();
      const panel: PanelNode = {
        id: id,
        children: [],
        // layout: "horizontal",
        // percentOfParent: Percent(0.5),
        ...{ ...PanelNodePropsOptional, ...props },
      };
      tree[id] = panel;

      return id;
    }),

  getPanel: (
    tree: PanelTreeData,
    panelId: PanelId,
    parentId?: PanelId,
  ): Effect.Effect<PanelNode, PanelDoesNotExistError> => {
    const panel = tree[panelId];
    if (!panel)
      return Effect.fail(new PanelDoesNotExistError(panelId)).pipe(
        Effect.mapError((err) =>
          Match.value(err).pipe(
            Match.tag("PanelDoesNotExistError", (err) =>
              parentId ? err.parent(parentId) : err,
            ),
            Match.orElse((err) => err),
          ),
        ),
      );
    return Effect.succeed(panel);
  },

  addChild: (
    treeStore: PanelTreeStore,
    parentId: PanelId,
    newChildId: PanelId,
  ): Effect.Effect<void, PanelDoesNotExistError> =>
    produceUpdate(treeStore, (tree) =>
      Effect.gen(function* () {
        // This keep the ratio of sizes of existing panels while adding
        // a new one still trying to honor its percent

        const parent = yield* panels.getPanel(tree, parentId, parentId);
        const newChild = yield* panels.getPanel(tree, newChildId, parentId);

        const n = parent.children.length;
        newChild.parent = parentId;

        let sum = 0;
        for (const childId of parent.children) {
          const child = yield* panels.getPanel(tree, childId, parentId);
          sum += child.percentOfParent;
        }

        const pNew = Order.clamp(Order.number)({
          minimum: 0,
          maximum: 1,
        })(newChild.percentOfParent / (n + 1));

        if (sum <= 0) {
          if (n === 0) {
            newChild.percentOfParent = Percent(1);
            parent.children.push(newChildId);
            return Effect.succeed(void {});
          }

          const each = (1 - pNew) / n;

          for (const childId of parent.children) {
            const child = yield* panels.getPanel(tree, childId, parentId);
            child.percentOfParent = Percent(each);
          }
          newChild.percentOfParent = Percent(pNew);
          parent.children.push(newChildId);

          return Effect.succeed(void {});
        }

        const scale = (1 - pNew) / sum;

        for (const childId of parent.children) {
          const child = yield* panels.getPanel(tree, childId, parentId);
          child.percentOfParent = Percent(child.percentOfParent * scale);
        }

        newChild.percentOfParent = Percent(pNew);
        parent.children.push(newChildId);

        return Effect.succeed(void {});
      }),
    ),

  deletePanel: (
    treeStore: PanelTreeStore,
    panelId: PanelId,
    removeFromParent: boolean = true,
  ): Effect.Effect<void, CannotDeleteRootPanelError | PanelDoesNotExistError> =>
    produceUpdate(treeStore, (tree) =>
      Effect.gen(function* () {
        if (panelId === "__root")
          return Effect.fail(new CannotDeleteRootPanelError());

        const panel = yield* panels.getPanel(tree, panelId);

        if (removeFromParent && panel.parent) {
          const parent = yield* panels.getPanel(tree, panel.parent);
          const idx = parent.children.findIndex((id) => id === panelId);
          parent.children.splice(idx, 1);
          panel.parent = undefined;
        }

        return Effect.forEach([...panel.children], (child) =>
          panels.deletePanel(treeStore, child, false),
        ).pipe(
          Effect.mapError((err) =>
            Match.value(err).pipe(
              Match.tag("PanelDoesNotExistError", (err) => err.parent(panelId)),
              Match.orElse((err) => err),
            ),
          ),
          Effect.flatMap(() => {
            delete tree[panelId];

            console.log(`deleted panel: '${panelId}'-'${panel.dbgName}'`);
            return Effect.succeed(void {});
          }),
          Effect.runSync,
        );
      }),
    ),

  update: (
    treeStore: PanelTreeStore,
    panelId: PanelId,
    props: Partial<PanelNodeProps>,
  ): Effect.Effect<void, PanelDoesNotExistError> =>
    produceUpdate(treeStore, (tree) => {
      return panels.getPanel(tree, panelId).pipe(
        Effect.tap((panel) => {
          const updatedPanel = { ...panel, ...props };
          tree[panelId] = updatedPanel;

          console.log(`updated panel: '${panelId}'-'${panel.dbgName}'`);
          return Effect.succeed(void {});
        }),
      );
    }),

  validateChildrenSizes: (
    treeData: PanelTreeData,
    panelId: PanelId,
  ): Effect.Effect<{ ok: boolean; difference: number }, never> => {
    const panel = treeData[panelId];

    if (panel.children.length === 0)
      return Effect.succeed({ ok: true, difference: 0 });

    let sum = 0;
    for (const childId of panel.children) {
      const child = treeData[childId];
      if (!child) continue;
      sum += child.percentOfParent;
    }

    return Effect.succeed({ ok: sum === 1, difference: Math.abs(sum - 1) });
  },
};

export type PanelEventEmitter = Emitter<PanelEvent>;
export type PanelEvent = Data.TaggedEnum<{
  addChild: {
    id: PanelId;
    childId: PanelId;
  };
  select: {
    id: PanelId | null;
  };
  delete: {
    id: PanelId;
  };
  update: {
    id: PanelId;
    props: Partial<PanelNodeProps>;
  };
}>;
export const PanelEvent = Data.taggedEnum<PanelEvent>();
