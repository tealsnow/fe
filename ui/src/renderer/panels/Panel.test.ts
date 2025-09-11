import { it, expect, describe } from "@effect/vitest";

import { Effect, Exit, Option } from "effect";
import { createStore } from "solid-js/store";

import * as Panel from "./Panel";
import { storeUpdate } from "~/lib/SignalObject";

const createTreeStore = (): [Panel.Tree, Panel.SetTree] => {
  const [tree, setTree] = createStore<Panel.Tree>(
    Panel.Tree.create.pipe(Effect.runSync),
  );
  return [tree, setTree];
};

const test = (
  name: string,
  fn: (tree: Panel.Tree, setTree: Panel.SetTree) => void,
) => {
  it.effect(name, () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();
      fn(tree, setTree);
    }),
  );
};

describe("creating/adding", () => {
  test("can create leaf nodes", function* (tree, setTree) {
    expect(Object.entries(tree.nodes)).toHaveLength(1);

    const a = yield* Panel.Node.Leaf.create(setTree, { title: "a" });
    const b = yield* Panel.Node.Leaf.create(setTree, { title: "b" });
    const c = yield* Panel.Node.Leaf.create(setTree, { title: "c" });

    expect(Object.entries(tree.nodes)).toHaveLength(4);

    const ids = [a, b, c];
    const titles = ["a", "b", "c"];

    const zipped: [Panel.ID.Leaf, string][] = ids.map((id, idx) => [
      id,
      titles[idx],
    ]);

    yield* Effect.forEach(zipped, ([id, title]) =>
      Effect.gen(function* () {
        const panel = yield* Panel.Node.Leaf.get(tree, { id });
        expect(panel).toBeDefined();
        expect(panel.title).toBe(title);
        return Effect.void;
      }),
    );
  });

  test("can add child - leaf", function* (tree, setTree) {
    const root = tree.root;
    const a = yield* Panel.Node.Leaf.create(setTree, { title: "a" });

    const rootPanel = yield* Panel.Node.Parent.get(tree, { id: root });

    expect(rootPanel.layout.children).toHaveLength(0);

    yield* Panel.Node.Parent.addChild(setTree, { parentId: root, childId: a });

    expect(rootPanel.layout.children).toHaveLength(1);
    expect(rootPanel.layout.children).toContain(a);

    const aPanel = yield* Panel.Node.Leaf.get(tree, { id: a });

    expect(aPanel.parent).toStrictEqual(Option.some(root));
    expect(aPanel.percentOfParent).toBe(1);
  });

  test("can add child - parent", function* (tree, setTree) {
    const root = tree.root;
    const a = yield* Panel.Node.Parent.create(setTree, {});

    const rootPanel = yield* Panel.Node.Parent.get(tree, { id: root });

    expect(rootPanel.layout.children).toHaveLength(0);

    yield* Panel.Node.Parent.addChild(setTree, { parentId: root, childId: a });

    expect(rootPanel.layout.children).toHaveLength(1);
    expect(rootPanel.layout.children).toContain(a);

    const aPanel = yield* Panel.Node.Parent.get(tree, { id: a });

    expect(aPanel.parent).toStrictEqual(Option.some(root));
    expect(aPanel.percentOfParent).toBe(1);
    expect(aPanel.layout.children).toHaveLength(0);
  });

  test("can add children", function* (tree, setTree) {
    const parent = yield* Panel.Node.Parent.create(setTree, {});
    const a = yield* Panel.Node.Leaf.create(setTree, { title: "a" });
    const b = yield* Panel.Node.Leaf.create(setTree, { title: "b" });

    const parentPanel = yield* Panel.Node.Parent.getOrError(tree, {
      id: parent,
    });
    expect(parentPanel.layout.children).toHaveLength(0);

    yield* Panel.Node.Parent.addChild(setTree, {
      parentId: tree.root,
      childId: parent,
    });
    yield* Panel.Node.Parent.addChild(setTree, {
      parentId: parent,
      childId: a,
    });
    yield* Panel.Node.Parent.addChild(setTree, {
      parentId: parent,
      childId: b,
    });

    // const childrenValid = yield* Panel.validateChildrenSizes(tree, { id: root });
    // expect(childrenValid).toStrictEqual({ ok: true, difference: 0 });

    const aPanel = yield* Panel.Node.Leaf.get(tree, { id: a });
    const bPanel = yield* Panel.Node.Leaf.get(tree, { id: b });

    expect(parentPanel.parent).toStrictEqual(Option.some(tree.root));
    expect(parentPanel.percentOfParent).toBe(1);
    expect(aPanel.parent).toStrictEqual(Option.some(parentPanel));
    expect(aPanel.percentOfParent).toBe(0.5);
    expect(bPanel.parent).toStrictEqual(Option.some(parentPanel));
    expect(bPanel.percentOfParent).toBe(0.5);
  });

  test("can add children while keeping ratio", function* (tree, setTree) {
    const root = tree.root;
    const a = yield* Panel.Node.Leaf.create(setTree, {
      title: "a",
      percentOfParent: Panel.Percent(1),
    });
    const b = yield* Panel.Node.Leaf.create(setTree, {
      title: "b",
      percentOfParent: Panel.Percent(0.5),
    });

    const rootPanel = yield* Panel.Node.Parent.get(tree, { id: root });

    expect(rootPanel.layout.children).toHaveLength(0);

    yield* Panel.Node.Parent.addChild(setTree, { parentId: root, childId: a });
    yield* Panel.Node.Parent.addChild(setTree, { parentId: root, childId: b });

    const aPanel = yield* Panel.Node.Leaf.get(tree, { id: a });
    const bPanel = yield* Panel.Node.Leaf.get(tree, { id: b });

    // const childrenValid = yield* Panel.validateChildrenSizes(tree, {
    //   id: root,
    // });
    // expect(childrenValid).toStrictEqual({ ok: true, difference: 0 });

    expect(aPanel.parent).toStrictEqual(Option.some(root));
    expect(aPanel.percentOfParent).toBe(0.75);
    expect(bPanel.parent).toStrictEqual(Option.some(root));
    expect(bPanel.percentOfParent).toBe(0.25);
  });

  test("errors when parent does not exist", function* (tree, setTree) {
    const fakeParent = yield* Panel.ID.create.Parent;

    const a = yield* Panel.Node.Leaf.create(setTree, { title: "a" });

    expect(tree.nodes[a.uuid]).toBeDefined();
    expect(Object.entries(tree.nodes)).toHaveLength(2);

    const result = yield* Effect.exit(
      Panel.Node.Parent.addChild(setTree, { parentId: fakeParent, childId: a }),
    );

    expect(JSON.stringify(result)).toStrictEqual(
      JSON.stringify(
        Exit.fail(new Panel.NodeNotInTreeError({ id: fakeParent })),
      ),
    );
  });

  test("errors when child does not exist", function* (tree, setTree) {
    const a = yield* Panel.Node.Parent.create(setTree, {});

    const fakeChild = yield* Panel.ID.create.Leaf;

    expect(tree.nodes[a.uuid]).toBeDefined();
    expect(Object.entries(tree.nodes)).toHaveLength(2);

    const result = yield* Effect.exit(
      Panel.Node.Parent.addChild(setTree, { parentId: a, childId: fakeChild }),
    );

    expect(JSON.stringify(result)).toStrictEqual(
      JSON.stringify(
        Exit.fail(new Panel.NodeNotInTreeError({ id: fakeChild })),
      ),
    );
  });

  test("errors when there is an existing parent", function* (_tree, setTree) {
    const parentA = yield* Panel.Node.Parent.create(setTree, {});
    const parentB = yield* Panel.Node.Parent.create(setTree, {});

    const a = yield* Panel.Node.Leaf.create(setTree, { title: "a" });

    yield* Panel.Node.Parent.addChild(setTree, {
      parentId: parentA,
      childId: a,
    });

    const result = yield* Effect.exit(
      Panel.Node.Parent.addChild(setTree, { parentId: parentB, childId: a }),
    );

    expect(JSON.stringify(result)).toStrictEqual(
      JSON.stringify(Exit.fail(new Panel.NodeAlreadyHasParentError({ id: a }))),
    );
  });
});

describe("deleting", () => {
  test("can delete single leaf node", function* (tree, setTree) {
    const a = yield* Panel.Node.Leaf.create(setTree, { title: "a" });

    expect(tree.nodes[a.uuid]).toBeDefined();
    expect(Object.entries(tree.nodes)).toHaveLength(2);

    yield* Panel.Node.destroy(setTree, { id: a });

    expect(tree.nodes[a.uuid]).toBeUndefined();
    expect(Object.entries(tree.nodes)).toHaveLength(1);
  });

  test("can delete panel with children", function* (tree, setTree) {
    const a = yield* Panel.Node.Parent.create(setTree, {});
    const b = yield* Panel.Node.Leaf.create(setTree, { title: "b" });
    const c = yield* Panel.Node.Leaf.create(setTree, { title: "c" });

    yield* Panel.Node.Parent.addChild(setTree, { parentId: a, childId: b });
    yield* Panel.Node.Parent.addChild(setTree, { parentId: a, childId: c });

    yield* Panel.Node.destroy(setTree, { id: a });

    expect(tree.nodes[a.uuid]).toBeUndefined();
    expect(tree.nodes[b.uuid]).toBeUndefined();
    expect(tree.nodes[c.uuid]).toBeUndefined();
  });

  test("removes from parent", function* (tree, setTree) {
    const a = yield* Panel.Node.Parent.create(setTree, {});
    const b = yield* Panel.Node.Leaf.create(setTree, { title: "b" });
    const c = yield* Panel.Node.Leaf.create(setTree, { title: "c" });

    yield* Panel.Node.Parent.addChild(setTree, { parentId: a, childId: b });
    yield* Panel.Node.Parent.addChild(setTree, { parentId: a, childId: c });

    const aPanel = yield* Panel.Node.Parent.get(tree, { id: a });

    expect(aPanel.layout.children).toContain(b);
    expect(aPanel.layout.children).toContain(c);

    yield* Panel.Node.destroy(setTree, { id: b });

    expect(aPanel.layout.children).not.toContain(b);
    expect(aPanel.layout.children).toContain(c);

    expect(tree.nodes[a.uuid]).toBeDefined();
    expect(tree.nodes[b.uuid]).toBeUndefined();
    expect(tree.nodes[c.uuid]).toBeDefined();
  });

  test("redistributes simple", function* (tree, setTree) {
    const root = tree.root;
    const a = yield* Panel.Node.Leaf.create(setTree, { title: "a" });
    const b = yield* Panel.Node.Leaf.create(setTree, {
      title: "b",
      percentOfParent: Panel.Percent(0.5),
    });

    yield* Panel.Node.Parent.addChild(setTree, { parentId: root, childId: a });
    yield* Panel.Node.Parent.addChild(setTree, { parentId: root, childId: b });

    expect(tree.nodes[a.uuid].percentOfParent).toBe(Panel.Percent(0.75));
    expect(tree.nodes[b.uuid].percentOfParent).toBe(Panel.Percent(0.25));

    yield* Panel.Node.destroy(setTree, { id: b });

    expect(tree.nodes[b.uuid]).toBeUndefined();
    expect(tree.nodes[a.uuid].percentOfParent).toBe(Panel.Percent(1));
  });

  test("redistributes complex", function* (tree, setTree) {
    const root = tree.root;
    const a = yield* Panel.Node.Leaf.create(setTree, { title: "a" });
    const b = yield* Panel.Node.Leaf.create(setTree, { title: "b" });
    const c = yield* Panel.Node.Leaf.create(setTree, { title: "b" });

    yield* Panel.Node.Parent.addChild(setTree, { parentId: root, childId: a });
    yield* Panel.Node.Parent.addChild(setTree, { parentId: root, childId: b });
    yield* Panel.Node.Parent.addChild(setTree, { parentId: root, childId: c });

    // setup complex sizes
    storeUpdate(setTree, (tree) => {
      tree.nodes[a.uuid].percentOfParent = Panel.Percent(0.5);
      tree.nodes[b.uuid].percentOfParent = Panel.Percent(0.3);
      tree.nodes[c.uuid].percentOfParent = Panel.Percent(0.2);
    });

    yield* Panel.Node.destroy(setTree, { id: c });

    expect(tree.nodes[c.uuid]).toBeUndefined();
    expect(tree.nodes[a.uuid].percentOfParent).toBe(Panel.Percent(0.625)); // 0.5/0.8
    expect(tree.nodes[b.uuid].percentOfParent).toBe(Panel.Percent(0.375)); // 0.3/0.8
  });

  test("errors on delete root panel", function* (tree, setTree) {
    const result = yield* Effect.exit(
      Panel.Node.destroy(setTree, { id: tree.root }),
    );

    expect(JSON.stringify(result)).toStrictEqual(
      JSON.stringify(Exit.fail(new Panel.CannotDeleteRootError())),
    );
  });

  test("errors on delete panel with nonexistent child", function* (tree, setTree) {
    const a = yield* Panel.Node.Parent.create(setTree, {});
    const b = yield* Panel.Node.Leaf.create(setTree, { title: "b" });

    const fakeId = yield* Panel.ID.create.Leaf;

    yield* Panel.Node.Parent.addChild(setTree, { parentId: a, childId: b });

    yield* storeUpdate(setTree, (tree) =>
      Effect.gen(function* () {
        const panel = yield* Panel.Node.Parent.get(tree, { id: a });
        panel.layout.children.push(fakeId);
      }),
    );

    const aPanel = yield* Panel.Node.Parent.get(tree, { id: a });

    expect(aPanel).toBeDefined();
    expect(aPanel.layout.children).toHaveLength(2);
    expect(Object.entries(tree.nodes)).toHaveLength(3);

    const result = yield* Effect.exit(Panel.Node.destroy(setTree, { id: a }));

    expect(JSON.stringify(result)).toStrictEqual(
      JSON.stringify(
        Exit.fail(new Panel.NodeNotInTreeError({ id: fakeId }).withParent(a)),
      ),
    );

    expect(tree.nodes[a.uuid]).toBeDefined();
    expect(aPanel.layout.children).toHaveLength(2);
    expect(Object.entries(tree.nodes)).toHaveLength(3);
  });
});
