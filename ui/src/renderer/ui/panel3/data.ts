import { Component } from "solid-js";
import { Array, Data, Effect, Option } from "effect";

import Integer from "~/lib/Integer";
import Percent from "~/lib/Percent";
import UUID from "~/lib/UUID";
import { PickPartial } from "~/lib/type_helpers";
import assert from "~/lib/assert";

export type Leaf = {
  id: LeafID;
};
export const Leaf = Data.case<Leaf>();

export const makeLeaf = (id: LeafID = UUID.make()): Leaf => Leaf({ id });

export type PanelNode = Data.TaggedEnum<{
  Split: {
    axis: SplitAxis;
    children: SplitChild[];
  };
  Tabs: {
    active: Option.Option<Integer>;
    children: Leaf[];
  };
}>;
export namespace PanelNode {
  export const PanelNodeCtor = Data.taggedEnum<PanelNode>();

  export const $is = PanelNodeCtor.$is;
  export const $match = PanelNodeCtor.$match;

  export type Split = Data.TaggedEnum.Value<PanelNode, "Split">;
  export type Tabs = Data.TaggedEnum.Value<PanelNode, "Tabs">;

  export const Split = PanelNodeCtor.Split;
  export const Tabs = PanelNodeCtor.Tabs;

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

export const splitAddChild = ({
  split,
  child,
  idx = undefined,
}: {
  split: PanelNode.Split;
  child: PanelNode;
  idx?: Integer;
}): Effect.Effect<PanelNode.Split> =>
  Effect.sync(() => {
    if (idx) assert(idx <= split.children.length);

    const old = split.children;
    const n = old.length;

    if (n === 0) {
      return PanelNode.Split({
        ...split,
        children: [{ percent: Percent(1), node: child }],
      });
    }

    const newShare = 1 / (n + 1);

    const scaled = old.map((c) => ({
      ...c,
      percent: Percent(c.percent * (1 - newShare)),
    }));

    const insertAt = idx === undefined ? scaled.length : idx;

    const children = [
      ...scaled.slice(0, insertAt),
      { percent: Percent(newShare), node: child },
      ...scaled.slice(insertAt),
    ];

    // NOTE: not sure if this is really needed, but added it anyway
    // Fix rounding drift so sum = 1
    const total = children.reduce((s, c) => s + c.percent, 0);
    const drift = 1 - total;
    if (Math.abs(drift) > 1e-12) {
      const last = children[children.length - 1];
      children[children.length - 1] = {
        ...last,
        percent: Percent(last.percent + drift),
      };
    }

    return PanelNode.Split({ ...split, children });
  });

export const splitUpdateChildPercent = ({
  split,
  idx,
  percent,
}: {
  split: PanelNode.Split;
  idx: Integer;
  percent: Percent;
}): Effect.Effect<PanelNode.Split> =>
  Effect.sync(() => {
    assert(idx >= 0 && idx <= split.children.length);
    return PanelNode.Split({
      ...split,
      children: split.children.map((c, i) =>
        i === idx ? { ...c, percent } : c,
      ),
    });
  });

/**
 * Add a new tab to an existing tab node
 */
export const tabsAddTab = ({
  tabs,
  newLeaf,
  idx,
}: {
  tabs: PanelNode.Tabs;
  newLeaf: Leaf;
  idx?: Integer;
}): Effect.Effect<PanelNode.Tabs> =>
  Effect.sync(() => {
    if (idx !== undefined && idx !== tabs.children.length) {
      assert(idx < tabs.children.length);
      return PanelNode.Tabs({
        ...tabs,
        active: Option.some(idx),
        children: Option.getOrThrow(
          Array.insertAt(tabs.children, idx, newLeaf),
        ),
      });
    } else {
      return PanelNode.Tabs({
        ...tabs,
        active: Option.some(Integer(tabs.children.length)), // make new one active
        children: [...tabs.children, newLeaf],
      });
    }
  });

export const tabsSelect = ({
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

export const sidebarUpdate = ({
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

export const sidebarToggle = ({
  sidebars,
  side,
}: {
  sidebars: WorkspaceSidebars;
  side: WorkspaceSidebarSide;
}): Effect.Effect<WorkspaceSidebars> =>
  sidebarUpdate({
    sidebars,
    side,
    update: {
      enabled: !sidebars[side].enabled,
    },
  });
