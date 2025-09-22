import { describe, it, expect } from "@effect/vitest";
import { Effect, Exit, Option } from "effect";

import UUID from "~/lib/UUID";
import Percent from "~/lib/Percent";

import {
  PanelNode,
  splitLeaf,
  addTab,
  tabify,
  replaceChild,
  closeLeaf,
  updateNode,
  toggleSidebar,
  updateSidebar,
  Workspace,
  NodeNotFoundError,
} from "./data";

const mkLeaf = (): PanelNode.Leaf =>
  PanelNode.Leaf({
    id: UUID.make(),
  });

describe("PanelNode operations", () => {
  it.effect("can split a leaf", () =>
    Effect.gen(function* () {
      const a = mkLeaf();
      const b = mkLeaf();

      const split = yield* splitLeaf({
        leaf: a,
        axis: "horizontal",
        newLeaf: b,
        ratio: [Percent.from(50), Percent.from(50)],
      });

      expect(split.axis).toBe("horizontal");
      expect(split.children).toHaveLength(2);
      expect(split.children[0].node).toEqual(a);
      expect(split.children[1].node).toEqual(b);
    }),
  );

  it.effect("can add a tab", () =>
    Effect.gen(function* () {
      const a = mkLeaf();
      const tab = PanelNode.Tabs({ active: Option.none(), children: [a] });
      const b = mkLeaf();

      const updated = yield* addTab({ tab, newLeaf: b });

      expect(updated.children).toHaveLength(2);
      expect(Option.getOrUndefined(updated.active)).toBe(1);
    }),
  );

  it.effect("can tabify a leaf", () =>
    Effect.gen(function* () {
      const a = mkLeaf();
      const b = mkLeaf();

      const tab = yield* tabify({ leaf: a, newLeaf: b });

      expect(tab.children).toHaveLength(2);
      expect(Option.getOrUndefined(tab.active)).toBe(0);
    }),
  );

  it.effect("can replace a child in split", () =>
    Effect.gen(function* () {
      const a = mkLeaf();
      const b = mkLeaf();
      const c = mkLeaf();

      const split = yield* splitLeaf({
        leaf: a,
        axis: "vertical",
        newLeaf: b,
        ratio: [Percent.from(50), Percent.from(50)],
      });

      const replaced = yield* replaceChild({
        parent: split,
        oldNode: b,
        newNode: c,
      });

      expect(PanelNode.$is("Split")(replaced));
      expect(
        (replaced as PanelNode.Split).children.some((ch) => ch.node === c),
      );
      expect(
        (replaced as PanelNode.Split).children.some((ch) => ch.node === b),
      ).toBe(false);
    }),
  );

  it.effect("can close a leaf", () =>
    Effect.gen(function* () {
      const a = mkLeaf();
      const b = mkLeaf();

      const split = yield* splitLeaf({
        leaf: a,
        axis: "horizontal",
        newLeaf: b,
      });

      const closed = yield* closeLeaf({ node: split, id: a.id });

      // should collapse to just b
      expect(PanelNode.$is("Leaf")(closed));
      expect((closed as PanelNode.Leaf).id).toBe(b.id);
    }),
  );

  it.effect("updateNode finds and updates", () =>
    Effect.gen(function* () {
      const a = mkLeaf();
      const b = mkLeaf();

      const split = yield* splitLeaf({
        leaf: a,
        axis: "horizontal",
        newLeaf: b,
      });

      const res = yield* updateNode({
        node: split,
        match: (n) => PanelNode.$is("Leaf")(n) && n.id === a.id,
        fn: (_n) => PanelNode.Leaf({ id: b.id }),
      });

      expect(PanelNode.$is("Split")(res));
      const foundIds = (res as PanelNode.Split).children.map((c) => c.node);
      expect(foundIds.some((n) => PanelNode.$is("Leaf")(n)));
      expect(foundIds.some((n) => (n as PanelNode.Leaf).id === b.id));
    }),
  );

  it.effect("updates deeply nested leaf", () =>
    Effect.gen(function* () {
      const a = mkLeaf();
      const b = mkLeaf();

      // Split root into a and b
      const split = yield* splitLeaf({
        leaf: a,
        axis: "horizontal",
        newLeaf: b,
      });

      // Tabify b with a new leaf c
      const c = mkLeaf();
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
      const a = mkLeaf();
      const b = mkLeaf();
      const c = mkLeaf();

      const root: PanelNode = PanelNode.Split({
        axis: "horizontal",
        children: [
          { percent: Percent.from(33), node: a },
          {
            percent: Percent.from(33),
            node: PanelNode.Tabs({ active: Option.none(), children: [b, c] }),
          },
          { percent: Percent.from(34), node: mkLeaf() },
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
      const a = mkLeaf();

      const result = yield* Effect.exit(
        updateNode({
          node: a,
          match: (n) => PanelNode.$is("Leaf")(n) && false,
          fn: (n) => n,
        }),
      );

      expect(result).toEqual(Exit.fail(new NodeNotFoundError()));
    }),
  );

  it.effect("toggle sidebar flips enabled", () =>
    Effect.gen(function* () {
      const a = mkLeaf();
      const ws = Workspace({
        root: a,
        sidebars: {
          left: { enabled: false, node: a },
          right: { enabled: false, node: a },
          bottom: { enabled: false, node: a },
        },
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
      const a = mkLeaf();
      const b = mkLeaf();
      const ws = Workspace({
        root: a,
        sidebars: {
          left: { enabled: true, node: a },
          right: { enabled: false, node: a },
          bottom: { enabled: false, node: a },
        },
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
