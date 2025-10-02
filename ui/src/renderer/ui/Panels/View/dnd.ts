import { batch } from "solid-js";
import { Option, Effect, Match, Array } from "effect";

import {
  DragLocationHistory,
  ElementDragPayload,
} from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";

import Integer from "~/lib/Integer";
import { taggedCtor } from "~/lib/taggedCtor";
import UpdateFn from "~/lib/UpdateFn";

import { Context } from "../Context";
import {
  PanelNode,
  SplitAxis,
  splitAddChild,
  tabsAddTab,
  splitAxisCross,
  updateNodesInWorkspace,
  WorkspaceSidebar,
  Leaf,
} from "../data";

export type DragDataForTab = Readonly<{
  _tag: "DragDataForTab";
  tabs: PanelNode.Tabs;
  updateTabs: UpdateFn<PanelNode.Tabs>;
  leaf: Leaf;
  idx: Integer;
}>;
export const DragDataForTab = taggedCtor<DragDataForTab>("DragDataForTab");

export type DropTargetDataForTab = Readonly<{
  _tag: "DropTargetDataForTab";
  tabs: PanelNode.Tabs;
  updateTabs: UpdateFn<PanelNode.Tabs>;
  idx: Option.Option<Integer>;
}>;
export const DropTargetDataForTab = taggedCtor<DropTargetDataForTab>(
  "DropTargetDataForTab",
);

export type DropTargetSplitInsert = Readonly<{
  _tag: "DropTargetSplitInsert";
  split: PanelNode.Split;
  updateSplit: UpdateFn<PanelNode.Split>;
  idx: Integer;
}>;
export const DropTargetSplitInsert = taggedCtor<DropTargetSplitInsert>(
  "DropTargetSplitInsert",
);

export const DropSide = ["left", "right", "top", "bottom"] as const;
export type DropSide = (typeof DropSide)[number];

export type DropTargetSplitTabs = Readonly<{
  _tag: "DropTargetSplitTabs";
  tabs: PanelNode.Tabs;
  side: DropSide;
}>;
export const DropTargetSplitTabs = taggedCtor<DropTargetSplitTabs>(
  "DropTargetSplitTabs",
);

export const handleDrop = (
  ctx: Context,
  source: ElementDragPayload,
  location: DragLocationHistory,
): void => {
  // @FIXME: we might need to check each drop target depending on how
  //   pdnd handles overlapping valid and invalid drop targets
  const destination = location.current.dropTargets[0];
  if (!destination) return;
  console.log("drop target count: ", location.current.dropTargets.length);

  Match.value({
    source: source.data,
    destination: destination.data,
  }).pipe(
    Match.when(
      {
        source: (source) => DragDataForTab.$is(source),
        destination: (destination) => DropTargetDataForTab.$is(destination),
      },
      ({ source, destination }) => {
        handle_DragDataForTab_on_DropTargetDataForTab(source, destination);
      },
    ),
    Match.when(
      {
        source: (source) => DragDataForTab.$is(source),
        destination: (destination) => DropTargetSplitInsert.$is(destination),
      },
      ({ source, destination }) =>
        handle_DragDataForTab_on_DropTargetSplitInsert(source, destination),
    ),
    Match.when(
      {
        source: (source) => DragDataForTab.$is(source),
        destination: (destination) => DropTargetSplitTabs.$is(destination),
      },
      ({ source, destination }) =>
        handle_DragDataForTab_on_DropTargetSplitTabs(ctx, source, destination),
    ),
    Match.orElse(() => {
      console.debug("no drop source/target pairs were matched");
    }),
  );
};

const handle_DragDataForTab_on_DropTargetDataForTab = (
  drag: DragDataForTab,
  dropTarget: DropTargetDataForTab,
): void => {
  batch(() => {
    drag.updateTabs((tabs) =>
      PanelNode.Tabs({
        ...tabs,
        children: tabs.children.filter((_, idx) => idx !== drag.idx),
      }),
    );
    dropTarget.updateTabs((tabs) =>
      tabsAddTab({
        tabs,
        newLeaf: drag.leaf,
        idx: Option.getOrUndefined(dropTarget.idx),
      }).pipe(Effect.runSync),
    );
  });
};

const handle_DragDataForTab_on_DropTargetSplitInsert = (
  drag: DragDataForTab,
  dropTarget: DropTargetSplitInsert,
): void => {
  batch(() => {
    drag.updateTabs((tabs) =>
      PanelNode.Tabs({
        ...tabs,
        children: tabs.children.filter((_, idx) => idx !== drag.idx),
      }),
    );
    dropTarget.updateSplit((split) =>
      splitAddChild({
        split,
        child: PanelNode.makeTabs({
          active: Integer(0),
          children: [drag.leaf],
        }),
        idx: dropTarget.idx,
      }).pipe(Effect.runSync),
    );
  });
};

const handle_DragDataForTab_on_DropTargetSplitTabs = (
  ctx: Context,
  drag: DragDataForTab,
  dropTarget: DropTargetSplitTabs,
): void => {
  batch(() => {
    drag.updateTabs((tabs) =>
      PanelNode.Tabs({
        ...tabs,
        children: tabs.children.filter((_, idx) => idx !== drag.idx),
      }),
    );

    const makeNewSplit = (
      axis: SplitAxis,
      existingNode: PanelNode,
    ): PanelNode => {
      return PanelNode.makeSplit({
        axis,
        children: Match.value(dropTarget.side).pipe(
          Match.whenOr("left", "top", () => [
            PanelNode.makeTabs({
              active: Integer(0),
              children: [drag.leaf],
            }),
            existingNode,
          ]),
          Match.whenOr("right", "bottom", () => [
            existingNode,
            PanelNode.makeTabs({
              active: Integer(0),
              children: [drag.leaf],
            }),
          ]),
          Match.exhaustive,
        ),
      });
    };

    const makeNewSplitForRoot = (node: PanelNode): PanelNode => {
      return makeNewSplit(
        Match.value(dropTarget.side).pipe(
          Match.withReturnType<SplitAxis>(),
          Match.whenOr("left", "right", () => "horizontal"),
          Match.whenOr("top", "bottom", () => "vertical"),
          Match.exhaustive,
        ),
        node,
      );
    };

    const tabsEqual = (tabs: PanelNode.Tabs, node: PanelNode): boolean =>
      PanelNode.$is("Tabs")(node) && node.id === tabs.id;

    Match.value(dropTarget.tabs).pipe(
      Match.when(
        (tabs) => tabsEqual(tabs, ctx.workspace.root),
        () => ctx.setWorkspace("root", (root) => makeNewSplitForRoot(root)),
      ),
      Match.when(
        (tabs) => tabsEqual(tabs, ctx.workspace.sidebars.left.node),
        () =>
          ctx.setWorkspace("sidebars", "left", (left) =>
            WorkspaceSidebar({
              ...left,
              node: makeNewSplitForRoot(left.node),
            }),
          ),
      ),
      Match.when(
        (tabs) => tabsEqual(tabs, ctx.workspace.sidebars.right.node),
        () =>
          ctx.setWorkspace("sidebars", "right", (right) =>
            WorkspaceSidebar({
              ...right,
              node: makeNewSplitForRoot(right.node),
            }),
          ),
      ),
      Match.when(
        (tabs) => tabsEqual(tabs, ctx.workspace.sidebars.bottom.node),
        () =>
          ctx.setWorkspace("sidebars", "bottom", (bottom) =>
            WorkspaceSidebar({
              ...bottom,
              node: makeNewSplitForRoot(bottom.node),
            }),
          ),
      ),
      Match.orElse(() => {
        ctx.setWorkspace((workspace) =>
          updateNodesInWorkspace({
            workspace,
            update: (split) => {
              if (!PanelNode.$is("Split")(split)) return Option.none();

              const idx = split.children.findIndex((c) =>
                tabsEqual(dropTarget.tabs, c.node),
              );
              if (idx === -1) return Option.none();

              return Option.some(
                PanelNode.Split({
                  ...split,
                  children: Array.modifyOption(split.children, idx, (c) => ({
                    ...c,
                    node: makeNewSplit(splitAxisCross[split.axis], c.node),
                  })).pipe(
                    Option.getOrThrowWith(
                      () =>
                        "unreachable: we just checked that the array contains this child",
                    ),
                  ),
                }),
              );
            },
          }).pipe(
            Option.getOrThrowWith(
              () => "failed to find parent split of tabs to turn into a split",
            ),
          ),
        );
      }),
    );
  });
};
