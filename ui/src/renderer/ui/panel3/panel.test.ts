import { describe, it, expect } from "@effect/vitest";
import { Effect, Exit, Option } from "effect";

import UUID from "~/lib/UUID";
import Percent from "~/lib/Percent";

import {
  PanelNode,
  splitLeaf,
  addTab,
  tabify,
  updateNode,
  toggleSidebar,
  updateSidebar,
  Workspace,
  NodeNotFoundError,
  WorkspaceSidebars,
  WorkspaceSidebar,
} from "./data";

describe("PanelNode operations", () => {
  it.effect("can split a leaf", () =>
    Effect.gen(function* () {
      const a = PanelNode.makeLeaf();
      const b = PanelNode.makeLeaf();

      const split = yield* splitLeaf({
        axis: "horizontal",
        leaf: a,
        newLeaf: b,
      });

      expect(split.axis).toBe("horizontal");
      expect(split.children).toHaveLength(2);
      expect(split.children[0].node).toEqual(a);
      expect(split.children[1].node).toEqual(b);
    }),
  );

  it.effect("can add a tab", () =>
    Effect.gen(function* () {
      const a = PanelNode.makeLeaf();
      const tabs = PanelNode.makeTabs({ children: [a] });
      const b = PanelNode.makeLeaf();

      const updated = yield* addTab({ tabs, newLeaf: b });

      expect(updated.children).toHaveLength(2);
      expect(Option.getOrUndefined(updated.active)).toBe(1);
    }),
  );

  it.effect("can tabify a leaf", () =>
    Effect.gen(function* () {
      const a = PanelNode.makeLeaf();
      const b = PanelNode.makeLeaf();

      const tab = yield* tabify({ leaf: a, newLeaf: b });

      expect(tab.children).toHaveLength(2);
      expect(Option.getOrUndefined(tab.active)).toBe(0);
    }),
  );

  // it.effect("can replace a child in split", () =>
  //   Effect.gen(function* () {
  //     const a = PanelNode.makeLeaf();
  //     const b = PanelNode.makeLeaf();
  //     const c = PanelNode.makeLeaf();

  //     const split = yield* splitLeaf({
  //       axis: "vertical",
  //       leaf: a,
  //       newLeaf: b,
  //     });

  //     const replaced = yield* replaceChild({
  //       parent: split,
  //       oldNode: b,
  //       newNode: c,
  //     });

  //     expect(PanelNode.$is("Split")(replaced));
  //     expect(
  //       (replaced as PanelNode.Split).children.some((ch) => ch.node === c),
  //     );
  //     expect(
  //       (replaced as PanelNode.Split).children.some((ch) => ch.node === b),
  //     ).toBe(false);
  //   }),
  // );

  // it.effect("can close a leaf", () =>
  //   Effect.gen(function* () {
  //     const a = PanelNode.makeLeaf();
  //     const b = PanelNode.makeLeaf();

  //     const split = yield* splitLeaf({
  //       axis: "horizontal",
  //       leaf: a,
  //       newLeaf: b,
  //     });

  //     const closed = yield* closeLeaf({ node: split, id: a.id });

  //     // should collapse to just b
  //     expect(PanelNode.$is("Leaf")(closed));
  //     expect((closed as PanelNode.Leaf).id).toBe(b.id);
  //   }),
  // );

  it.effect("updateNode finds and updates", () =>
    Effect.gen(function* () {
      const a = PanelNode.makeLeaf();
      const b = PanelNode.makeLeaf();

      const split = yield* splitLeaf({
        axis: "horizontal",
        leaf: a,
        newLeaf: b,
      });

      const res = yield* updateNode({
        node: split,
        match: (n) => PanelNode.$is("Leaf")(n) && n.id === a.id,
        fn: () => PanelNode.Leaf({ id: b.id }),
      });

      expect(PanelNode.$is("Split")(res));
      const foundIds = (res as PanelNode.Split).children.map((c) => c.node);
      expect(foundIds.some((n) => PanelNode.$is("Leaf")(n)));
      expect(foundIds.some((n) => (n as PanelNode.Leaf).id === b.id));
    }),
  );

  it.effect("updates deeply nested leaf", () =>
    Effect.gen(function* () {
      const a = PanelNode.makeLeaf();
      const b = PanelNode.makeLeaf();

      // Split root into a and b
      const split = yield* splitLeaf({
        axis: "horizontal",
        leaf: a,
        newLeaf: b,
      });

      // Tabify b with a new leaf c
      const c = PanelNode.makeLeaf();
      const tab = yield* tabify({ leaf: b, newLeaf: c });

      const root = PanelNode.Split({
        axis: "vertical",
        children: [
          split.children[0], // a
          { percent: Percent.from(50), node: tab }, // tab with b + c
        ],
      });

      // target = c
      const newId = UUID.make();
      const updated = yield* updateNode({
        node: root,
        match: (n) => PanelNode.$is("Leaf")(n) && n.id === c.id,
        fn: () => PanelNode.Leaf({ id: newId }),
      });

      // verify c was replaced
      expect(PanelNode.$is("Split")(updated));
      const tabNode = (updated as PanelNode.Split).children[1].node;
      expect(PanelNode.$is("Tabs")(tabNode));
      expect(
        (tabNode as PanelNode.Tabs).children.some(
          (n) => PanelNode.$is("Leaf")(n) && n.id === newId,
        ),
      );
    }),
  );

  it.effect("updates multiple matching leaves", () =>
    Effect.gen(function* () {
      const a = PanelNode.makeLeaf();
      const b = PanelNode.makeLeaf();
      const c = PanelNode.makeLeaf();

      const root: PanelNode = PanelNode.makeSplit({
        axis: "horizontal",
        children: [
          a,
          PanelNode.Tabs({ active: Option.none(), children: [b, c] }),
          PanelNode.makeLeaf(),
        ],
      });

      const newId = UUID.make();

      const updated = yield* updateNode({
        node: root,
        match: (n) => PanelNode.$is("Leaf")(n) && [a.id, b.id].includes(n.id),
        fn: () => PanelNode.Leaf({ id: newId }),
      });

      // Extract updated leaves
      const children = (updated as PanelNode.Split).children;
      const leftLeaf = children[0].node as PanelNode.Leaf;
      const tabNode = children[1].node as PanelNode.Tabs;
      const tabLeaves = tabNode.children.filter((n) =>
        PanelNode.$is("Leaf")(n),
      );

      expect(leftLeaf.id).toBe(newId);
      expect(tabLeaves.some((leaf) => leaf.id === newId));
      // c should remain unchanged
      expect(tabLeaves.some((leaf) => leaf.id === c.id));
    }),
  );

  it.effect("updateNode fails if not found", () =>
    Effect.gen(function* () {
      const a = PanelNode.makeLeaf();

      const result = yield* Effect.exit(
        updateNode({
          node: a,
          match: () => false,
          fn: (n) => n,
        }),
      );

      expect(result).toEqual(Exit.fail(new NodeNotFoundError()));
    }),
  );

  it.effect("toggle sidebar flips enabled", () =>
    Effect.gen(function* () {
      const a = PanelNode.makeLeaf();
      const ws = Workspace({
        root: a,
        sidebars: WorkspaceSidebars({
          left: WorkspaceSidebar({ node: a }),
          right: WorkspaceSidebar({ node: a }),
          bottom: WorkspaceSidebar({ node: a }),
        }),
      });

      const updated = yield* toggleSidebar({
        sidebars: ws.sidebars,
        side: "left",
      });

      expect(updated.left.enabled);
    }),
  );

  it.effect("updateSidebar replaces sidebar node", () =>
    Effect.gen(function* () {
      const a = PanelNode.makeLeaf();
      const b = PanelNode.makeLeaf();
      const ws = Workspace({
        root: a,
        sidebars: WorkspaceSidebars({
          left: WorkspaceSidebar({ node: a }),
          right: WorkspaceSidebar({ node: a }),
          bottom: WorkspaceSidebar({ node: a }),
        }),
      });

      const updated = yield* updateSidebar({
        sidebars: ws.sidebars,
        side: "left",
        update: {
          node: b,
        },
      });

      expect(updated.left.node).toEqual(b);
    }),
  );
});
