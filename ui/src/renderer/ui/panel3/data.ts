import { Component } from "solid-js";
import { Data, Effect, Either, Match, Option, pipe } from "effect";

import Integer from "~/lib/Integer";
import Percent from "~/lib/Percent";
import UUID from "~/lib/UUID";
import { LessThanBigIntSchemaId } from "effect/Schema";

export type PanelNode = Data.TaggedEnum<{
  Split: {
    axis: SplitAxis;
    children: SplitChild[];
  };
  Tabs: {
    active: Option.Option<Integer>;
    children: PanelNode[];
  };
  Leaf: {
    id: LeafID;
  };
}>;
export const PanelNode = Data.taggedEnum<PanelNode>();
export namespace PanelNode {
  export type Split = Data.TaggedEnum.Value<PanelNode, "Split">;
  export type Tabs = Data.TaggedEnum.Value<PanelNode, "Tabs">;
  export type Leaf = Data.TaggedEnum.Value<PanelNode, "Leaf">;
}

export type SplitAxis = "horizontal" | "vertical";

export type SplitChild = {
  percent: Percent;
  node: PanelNode;
};

export type LeafID = UUID;
export const LeafID = UUID;

export type LeafContent = {
  title: string;
  render: Component<{}>;
};
export const LeafContent = Data.case<LeafContent>();

export type LeafRecord = Record<LeafID, LeafContent>;

export type Workspace = {
  root: PanelNode;
  sidebars: WorkspaceSidebars;
};
export const Workspace = Data.case<Workspace>();

export type WorkspaceSidebars = Record<WorkspaceSidebarSide, WorkspaceSidebar>;
export const WorkspaceSidebars = Data.case<WorkspaceSidebars>();

export type WorkspaceSidebar = {
  enabled: boolean;
  node: PanelNode;
};

export type WorkspaceSidebarSide = "left" | "right" | "bottom";

/**
 * Split an existing leaf into a split with a optional new leaf
 */
export const splitLeaf = ({
  leaf,
  axis,
  newLeaf,
  ratio,
}: {
  leaf: PanelNode.Leaf;
  axis: SplitAxis;
} & (
  | {
      newLeaf: PanelNode.Leaf;
      ratio?: [Percent, Percent];
    }
  | {
      newLeaf?: PanelNode.Leaf;
      ratio?: never;
    }
)): Effect.Effect<PanelNode.Split> =>
  Effect.sync(() =>
    PanelNode.Split({
      axis,
      children: Option.match(Option.fromNullable(newLeaf), {
        onSome: (newLeaf) =>
          ratio
            ? [
                { percent: ratio[0], node: leaf },
                { percent: ratio[1], node: newLeaf },
              ]
            : [
                { percent: Percent(0.5), node: leaf },
                { percent: Percent(0.5), node: newLeaf },
              ],
        onNone: () => [{ percent: Percent(1), node: leaf }],
      }),
    }),
  );

/**
 * Add a new tab to an existing tab node
 */
export const addTab = ({
  tab,
  newLeaf,
}: {
  tab: PanelNode.Tabs;
  newLeaf: PanelNode.Leaf;
}): Effect.Effect<PanelNode.Tabs> =>
  Effect.sync(() =>
    PanelNode.Tabs({
      active: Option.some(Integer(tab.children.length)), // make new one active
      children: [...tab.children, newLeaf],
    }),
  );

/**
 * Wrap a leaf into a new tab node with another leaf
 */
export const tabify = ({
  leaf,
  newLeaf,
}: {
  leaf: PanelNode.Leaf;
  newLeaf?: PanelNode.Leaf;
}): Effect.Effect<PanelNode.Tabs> =>
  Effect.sync(() =>
    PanelNode.Tabs({
      active: Option.some(Integer(0)),
      children: newLeaf ? [leaf, newLeaf] : [leaf],
    }),
  );

export const selectTab = ({
  tabs,
  index,
}: {
  tabs: PanelNode.Tabs;
  index: Option.Option<Integer>;
}): Effect.Effect<PanelNode.Tabs> =>
  Effect.sync(() =>
    PanelNode.Tabs({
      ...tabs,
      active: index,
    }),
  );

/**
 * Replace a child node in a split or tab
 */
export const replaceChild = ({
  parent,
  oldNode,
  newNode,
}: {
  parent: PanelNode.Split | PanelNode.Tabs;
  oldNode: PanelNode;
  newNode: PanelNode;
}): Effect.Effect<typeof parent> =>
  Effect.sync(() =>
    Match.value(parent).pipe(
      Match.tag("Split", (split) =>
        PanelNode.Split({
          ...split,
          children: split.children.map((c) =>
            c.node === oldNode ? { ...c, node: newNode } : c,
          ),
        }),
      ),
      Match.tag("Tabs", (tab) =>
        PanelNode.Tabs({
          ...tab,
          children: tab.children.map((c) => (c === oldNode ? newNode : c)),
        }),
      ),
      Match.exhaustive,
    ),
  );

/**
 * Close a leaf by ID (prune from tree)
 */
export const closeLeaf = ({
  node,
  id,
}: {
  node: PanelNode;
  id: LeafID;
}): Effect.Effect<PanelNode | null> =>
  Effect.sync(() =>
    Match.value(node).pipe(
      Match.tag("Leaf", (leaf) => (leaf.id === id ? null : node)),
      Match.tag("Split", (split) => {
        const newChildren = split.children
          .map((c) => ({
            ...c,
            node: closeLeaf({ node: c.node, id }).pipe(Effect.runSync),
          }))
          .filter((c) => c.node !== null) as SplitChild[];
        if (newChildren.length === 0) return null;
        if (newChildren.length === 1) return newChildren[0].node;
        return { ...split, children: newChildren };
      }),
      Match.tag("Tabs", (tab) => {
        const tabChildren = tab.children
          .map((c) => closeLeaf({ node: c, id }).pipe(Effect.runSync))
          .filter((c) => c !== null) as PanelNode[];
        if (tabChildren.length === 0) return null;
        if (tabChildren.length === 1) return tabChildren[0];
        return { ...tab, children: tabChildren };
      }),
      Match.exhaustive,
    ),
  );

export class NodeNotFoundError extends Data.TaggedError(
  "NodeNotFoundError",
)<{}> {}

/**
 * calls `fn` on each node that matches the predicate `match`
 */
export const updateNode = ({
  node,
  match,
  fn,
}: {
  node: PanelNode;
  match: (n: PanelNode) => boolean;
  fn: (n: PanelNode) => PanelNode;
}): Effect.Effect<PanelNode, NodeNotFoundError> =>
  Effect.gen(function* () {
    if (match(node)) return fn(node);

    const testNode = (node: PanelNode): Effect.Effect<[boolean, PanelNode]> =>
      Effect.gen(function* () {
        const res = yield* Effect.either(updateNode({ node, match, fn }));
        return Either.isRight(res) ? [true, res.right] : [false, node];
      });

    return yield* Match.value(node).pipe(
      Match.tag("Leaf", () => Effect.fail(new NodeNotFoundError())),
      Match.tag("Split", (split) =>
        Effect.gen(function* () {
          let matched = false;
          const newChildren: typeof split.children = [];

          for (const c of split.children) {
            const [match, node] = yield* testNode(c.node);
            if (match) matched = true;
            newChildren.push({ ...c, node });
          }

          if (!matched) return yield* Effect.fail(new NodeNotFoundError());

          return PanelNode.Split({ ...split, children: newChildren });
        }),
      ),
      Match.tag("Tabs", (tab) =>
        Effect.gen(function* () {
          let matched = false;
          const newChildren: PanelNode[] = [];

          for (const c of tab.children) {
            const [match, node] = yield* testNode(c);
            if (match) matched = true;
            newChildren.push(node);
          }

          if (!matched) return yield* Effect.fail(new NodeNotFoundError());

          return PanelNode.Tabs({ ...tab, children: newChildren });
        }),
      ),
      Match.exhaustive,
    );
  });

export const updateSidebar = ({
  sidebars,
  side,
  update,
}: {
  sidebars: WorkspaceSidebars;
  side: WorkspaceSidebarSide;
  update: Partial<WorkspaceSidebar>;
}): Effect.Effect<WorkspaceSidebars> =>
  Effect.sync(() =>
    WorkspaceSidebars({
      ...sidebars,
      [side]: {
        ...sidebars[side],
        ...update,
      },
    }),
  );

export const toggleSidebar = ({
  sidebars,
  side,
}: {
  sidebars: WorkspaceSidebars;
  side: WorkspaceSidebarSide;
}): Effect.Effect<WorkspaceSidebars> =>
  updateSidebar({
    sidebars,
    side,
    update: {
      enabled: !sidebars[side].enabled,
    },
  });

export const addLeaf = ({
  record,
  content,
}: {
  record: LeafRecord;
  content: LeafContent;
}): Effect.Effect<[LeafRecord, PanelNode]> =>
  pipe(
    PanelNode.Leaf({ id: UUID.make() }),
    Effect.succeed,
    Effect.andThen((leaf) => [{ ...record, [leaf.id]: content }, leaf]),
  );
