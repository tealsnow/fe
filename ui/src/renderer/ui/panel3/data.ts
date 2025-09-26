import { Component } from "solid-js";
import { Data, Effect, Either, Equal, Match, Option } from "effect";

import Integer from "~/lib/Integer";
import Percent from "~/lib/Percent";
import UUID from "~/lib/UUID";
import OutOfBoundsError from "~/lib/OutOfBoundsError";
import { PickPartial } from "~/lib/type_helpers";
import assert from "~/lib/assert";

export type PanelNode = Data.TaggedEnum<{
  Split: {
    axis: SplitAxis;
    children: SplitChild[];
  };
  Tabs: {
    active: Option.Option<Integer>;
    children: PanelNode.Leaf[];
  };
  Leaf: {
    id: LeafID;
  };
}>;
export namespace PanelNode {
  export const PanelNodeCtor = Data.taggedEnum<PanelNode>();

  export const $is = PanelNodeCtor.$is;
  export const $match = PanelNodeCtor.$match;

  export type Split = Data.TaggedEnum.Value<PanelNode, "Split">;
  export type Tabs = Data.TaggedEnum.Value<PanelNode, "Tabs">;
  export type Leaf = Data.TaggedEnum.Value<PanelNode, "Leaf">;

  export type Parent = Split | Tabs;

  export const Split = PanelNodeCtor.Split;
  export const Tabs = PanelNodeCtor.Tabs;
  export const Leaf = PanelNodeCtor.Leaf;

  /**
   * Small helper for split to handle equal sizing for any number of children
   */
  export const makeSplit = ({
    axis,
    children = [],
  }: Omit<PanelNode.Split, "_tag" | "children"> & {
    children: PanelNode[];
  }): PanelNode.Split => {
    const each = Percent(1 / children.length);

    const newChildren: SplitChild[] = [];
    for (const child of children) {
      newChildren.push({ percent: each, node: child });
    }

    return PanelNode.Split({
      axis,
      children: newChildren,
    });
  };

  export const makeTabs = (
    {
      active,
      children,
    }: Omit<PanelNode.Tabs, "_tag" | "active"> & {
      active?: Integer;
    } = { children: [] },
  ): PanelNode.Tabs =>
    PanelNode.Tabs({
      active: Option.fromNullable(active),
      children,
    });

  export const makeLeaf = (id: LeafID = UUID.make()): PanelNode.Leaf =>
    PanelNode.Leaf({ id });
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

export type LeafRecord = Record<LeafID, Option.Option<LeafContent>>;

export type Workspace = {
  root: PanelNode;
  sidebars: WorkspaceSidebars;
};
export const Workspace = Data.case<Workspace>();

export type WorkspaceSidebars = Record<WorkspaceSidebarSide, WorkspaceSidebar>;
export const WorkspaceSidebars = Data.case<WorkspaceSidebars>();

export type WorkspaceSidebar = {
  enabled: boolean;
  size: Percent;
  node: PanelNode;
};
export const WorkspaceSidebar = ({
  enabled = true,
  size = Percent.from(25),
  node,
}: PickPartial<WorkspaceSidebar, "enabled" | "size">): WorkspaceSidebar =>
  Data.case<WorkspaceSidebar>()({
    enabled,
    size,
    node,
  });

export type WorkspaceSidebarSide = "left" | "right" | "bottom";

/**
 * Split an existing leaf into a split with a optional new leaf
 */
export const splitLeaf = ({
  axis,
  leaf,
  newLeaf,
  ratio,
}: {
  axis: SplitAxis;
  leaf: PanelNode.Leaf;
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

export const updateSplitChildPercent = ({
  split,
  childIndex,
  percent,
}: {
  split: PanelNode.Split;
  childIndex: Integer;
  percent: Percent;
}): Effect.Effect<PanelNode.Split, OutOfBoundsError> => {
  if (childIndex < 0 || childIndex >= split.children.length)
    return Effect.fail(new OutOfBoundsError({ index: childIndex }));
  return Effect.succeed(
    PanelNode.Split({
      ...split,
      children: split.children.map((c, i) =>
        i === childIndex ? { ...c, percent } : c,
      ),
    }),
  );
};

/**
 * Add a new tab to an existing tab node
 */
export const addTab = ({
  tabs,
  newLeaf,
  idx,
}: {
  tabs: PanelNode.Tabs;
  newLeaf: PanelNode.Leaf;
  idx?: Integer;
}): Effect.Effect<PanelNode.Tabs> =>
  Effect.sync(() => {
    if (idx !== undefined && idx !== tabs.children.length) {
      assert(idx < tabs.children.length);

      const newChildren = tabs.children;
      newChildren.splice(idx, 0, newLeaf);

      return PanelNode.Tabs({
        ...tabs,
        active: Option.some(idx),
        children: newChildren,
      });
    } else {
      return PanelNode.Tabs({
        ...tabs,
        active: Option.some(Integer(tabs.children.length)), // make new one active
        children: [...tabs.children, newLeaf],
      });
    }
  });

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

export const removeChild = ({
  parent,
  match,
}: {
  parent: PanelNode.Parent;
  match: (child: PanelNode) => boolean;
}): Effect.Effect<PanelNode.Parent, NodeNotFoundError> =>
  Match.value(parent).pipe(
    Match.tag("Split", (split) => {
      const newChildren = split.children.filter((c) => !match(c.node));

      if (Equal.equals(newChildren, split.children))
        return Effect.fail(new NodeNotFoundError());

      return Effect.succeed(
        PanelNode.Split({
          ...split,
          children: newChildren,
        }),
      );
    }),
    Match.tag("Tabs", (tabs) => {
      const newChildren = tabs.children.filter((c) => !match(c));

      if (Equal.equals(newChildren, tabs.children))
        return Effect.fail(new NodeNotFoundError());

      return Effect.succeed(
        PanelNode.Tabs({
          ...tabs,
          children: newChildren,
        }),
      );
    }),
    Match.exhaustive,
  );

// /**
//  * Replace a child node in a split or tab
//  */
// export const replaceChild = ({
//   parent,
//   oldNode,
//   newNode,
// }: {
//   parent: PanelNode.Split | PanelNode.Tabs;
//   oldNode: PanelNode;
//   newNode: PanelNode;
// }): Effect.Effect<typeof parent> =>
//   Effect.sync(() =>
//     Match.value(parent).pipe(
//       Match.tag("Split", (split) =>
//         PanelNode.Split({
//           ...split,
//           children: split.children.map((c) =>
//             c.node === oldNode ? { ...c, node: newNode } : c,
//           ),
//         }),
//       ),
//       Match.tag("Tabs", (tab) =>
//         PanelNode.Tabs({
//           ...tab,
//           children: tab.children.map((c) => (c === oldNode ? newNode : c)),
//         }),
//       ),
//       Match.exhaustive,
//     ),
//   );

// /**
//  * Close a leaf by ID (prune from tree)
//  */
// export const closeLeaf = ({
//   node,
//   id,
// }: {
//   node: PanelNode;
//   id: LeafID;
// }): Effect.Effect<PanelNode | null> =>
//   Effect.sync(() =>
//     Match.value(node).pipe(
//       Match.tag("Leaf", (leaf) => (leaf.id === id ? null : node)),
//       Match.tag("Split", (split) => {
//         const newChildren = split.children
//           .map((c) => ({
//             ...c,
//             node: closeLeaf({ node: c.node, id }).pipe(Effect.runSync),
//           }))
//           .filter((c) => c.node !== null) as SplitChild[];
//         if (newChildren.length === 0) return null;
//         if (newChildren.length === 1) return newChildren[0].node;
//         return { ...split, children: newChildren };
//       }),
//       Match.tag("Tabs", (tab) => {
//         const tabChildren = tab.children
//           .map((c) => closeLeaf({ node: c, id }).pipe(Effect.runSync))
//           .filter((c) => c !== null) as PanelNode[];
//         if (tabChildren.length === 0) return null;
//         if (tabChildren.length === 1) return tabChildren[0];
//         return { ...tab, children: tabChildren };
//       }),
//       Match.exhaustive,
//     ),
//   );

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
  match: (node: PanelNode) => boolean;
  fn: (node: PanelNode) => PanelNode;
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
            const [didMatch, node] = yield* testNode(c.node);
            if (didMatch) matched = true;
            newChildren.push({ ...c, node });
          }

          if (!matched) return yield* Effect.fail(new NodeNotFoundError());

          return PanelNode.Split({ ...split, children: newChildren });
        }),
      ),
      Match.tag("Tabs", (tab) =>
        Effect.gen(function* () {
          let matched = false;
          const newChildren: PanelNode.Leaf[] = [];

          for (const c of tab.children) {
            const [didMatch, node] = yield* testNode(c);
            if (didMatch) matched = true;
            assert(
              PanelNode.$is("Leaf")(node),
              "Child of PanelNode.Tabs must be a leaf",
            );
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

// export const addLeaf = ({
//   record,
//   content,
// }: {
//   record: LeafRecord;
//   content: LeafContent;
// }): Effect.Effect<[LeafRecord, PanelNode]> =>
//   pipe(
//     PanelNode.Leaf({ id: UUID.make() }),
//     Effect.succeed,
//     Effect.andThen((leaf) => [{ ...record, [leaf.id]: content }, leaf]),
//   );
