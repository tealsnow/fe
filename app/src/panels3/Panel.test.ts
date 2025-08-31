import { it, expect, describe } from "@effect/vitest";

import { Effect, Exit, Logger, Option } from "effect";
import { createStore } from "solid-js/store";

import * as Panel from "./Panel";
import { storeUpdate } from "~/lib/SignalObject";

const createTreeStore = (): [Panel.Tree, Panel.SetTree] => {
  const [tree, setTree] = createStore<Panel.Tree>(
    Panel.createTree.pipe(Effect.runSync),
  );
  return [tree, setTree];
};

it.effect("errors on get nonexistent panel", () =>
  Effect.gen(function* () {
    const [tree, _setTree] = createTreeStore();

    const id = yield* Panel.createId;
    const result = yield* Effect.exit(Panel.getNode(tree, { id }));

    // @HACK: something is internally different between the result error
    //  and the constructed error, so we stringify them to compare the
    //  values instead. `toEqual` / `toStrictEqual` does not work
    expect(JSON.stringify(result)).toStrictEqual(
      JSON.stringify(Exit.fail(new Panel.PanelDoesNotExistError(id))),
    );
  }),
);

describe("creating/adding", () => {
  it.effect("can create panels", () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();

      expect(Object.entries(tree.nodes)).toHaveLength(1);

      const a = yield* Panel.createNode(setTree, { dbgName: "a" });
      const b = yield* Panel.createNode(setTree, { dbgName: "b" });
      const c = yield* Panel.createNode(setTree, { dbgName: "c" });

      expect(Object.entries(tree.nodes)).toHaveLength(4);

      const ids = [a, b, c];
      const names = ["a", "b", "c"];

      const zipped: [Panel.ID, string][] = ids.map((id, idx) => [
        id,
        names[idx],
      ]);
      yield* Effect.forEach(zipped, ([id, name]) =>
        Effect.gen(function* () {
          const panel = yield* Panel.getNode(tree, { id });
          expect(panel).toBeDefined();
          expect(panel.dbgName).toBe(name);
          return Effect.void;
        }),
      );
    }).pipe(Effect.provide(Logger.pretty)),
  );

  it.effect("can add child", () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();

      const root = tree.root;
      const a = yield* Panel.createNode(setTree, { dbgName: "a" });

      const rootPanel = yield* Panel.getNode(tree, { id: root });

      expect(rootPanel.children).toHaveLength(0);

      yield* Panel.addChild(setTree, { parentId: root, newChildId: a });

      expect(rootPanel.children).toHaveLength(1);
      expect(rootPanel.children).toContain(a);

      const aPanel = yield* Panel.getNode(tree, { id: a });

      expect(aPanel.parent).toStrictEqual(Option.some(root));
      expect(aPanel.percentOfParent).toBe(1);
    }),
  );

  it.effect("can add children", () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();

      const root = tree.root;
      const a = yield* Panel.createNode(setTree, { dbgName: "a" });
      const b = yield* Panel.createNode(setTree, { dbgName: "b" });

      const rootPanel = yield* Panel.getNode(tree, { id: root });

      expect(rootPanel.children).toHaveLength(0);

      yield* Panel.addChild(setTree, { parentId: root, newChildId: a });
      yield* Panel.addChild(setTree, { parentId: root, newChildId: b });

      const aPanel = yield* Panel.getNode(tree, { id: a });
      const bPanel = yield* Panel.getNode(tree, { id: b });

      const childrenValid = yield* Panel.validateChildrenSizes(tree, {
        id: root,
      });
      expect(childrenValid).toStrictEqual({ ok: true, difference: 0 });

      expect(aPanel.parent).toStrictEqual(Option.some(root));
      expect(aPanel.percentOfParent).toBe(0.5);
      expect(bPanel.parent).toStrictEqual(Option.some(root));
      expect(bPanel.percentOfParent).toBe(0.5);
    }),
  );

  it.effect("can add children while keeping ratio", () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();

      const root = tree.root;
      const a = yield* Panel.createNode(setTree, {
        dbgName: "a",
        percentOfParent: Panel.Percent(1),
      });
      const b = yield* Panel.createNode(setTree, {
        dbgName: "b",
        percentOfParent: Panel.Percent(0.5),
      });

      const rootPanel = yield* Panel.getNode(tree, { id: root });

      expect(rootPanel.children).toHaveLength(0);

      yield* Panel.addChild(setTree, { parentId: root, newChildId: a });
      yield* Panel.addChild(setTree, { parentId: root, newChildId: b });

      const aPanel = yield* Panel.getNode(tree, { id: a });
      const bPanel = yield* Panel.getNode(tree, { id: b });

      const childrenValid = yield* Panel.validateChildrenSizes(tree, {
        id: root,
      });
      expect(childrenValid).toStrictEqual({ ok: true, difference: 0 });

      expect(aPanel.parent).toStrictEqual(Option.some(root));
      expect(aPanel.percentOfParent).toBe(0.75);
      expect(bPanel.parent).toStrictEqual(Option.some(root));
      expect(bPanel.percentOfParent).toBe(0.25);
    }),
  );

  it.effect("errors when parent does not exist", () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();

      const fakeParent = yield* Panel.createId;

      const a = yield* Panel.createNode(setTree, { dbgName: "a" });

      expect(tree.nodes[a]).toBeDefined();
      expect(Object.entries(tree.nodes)).toHaveLength(2);

      const result = yield* Effect.exit(
        Panel.addChild(setTree, { parentId: fakeParent, newChildId: a }),
      );

      expect(JSON.stringify(result)).toStrictEqual(
        JSON.stringify(Exit.fail(new Panel.PanelDoesNotExistError(fakeParent))),
      );
    }),
  );

  it.effect("errors when child does not exist", () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();

      const a = yield* Panel.createNode(setTree, { dbgName: "a" });

      const fakeChild = yield* Panel.createId;

      expect(tree.nodes[a]).toBeDefined();
      expect(Object.entries(tree.nodes)).toHaveLength(2);

      const result = yield* Effect.exit(
        Panel.addChild(setTree, { parentId: a, newChildId: fakeChild }),
      );

      expect(JSON.stringify(result)).toStrictEqual(
        JSON.stringify(Exit.fail(new Panel.PanelDoesNotExistError(fakeChild))),
      );
    }),
  );

  it.effect("errors when there is an existing parent", () =>
    Effect.gen(function* () {
      const [_tree, setTree] = createTreeStore();

      const parentA = yield* Panel.createNode(setTree, {
        dbgName: "parentA",
      });
      const parentB = yield* Panel.createNode(setTree, {
        dbgName: "parentB",
      });
      const a = yield* Panel.createNode(setTree, { dbgName: "a" });

      yield* Panel.addChild(setTree, { parentId: parentA, newChildId: a });

      const result = yield* Effect.exit(
        Panel.addChild(setTree, { parentId: parentB, newChildId: a }),
      );

      expect(JSON.stringify(result)).toStrictEqual(
        JSON.stringify(Exit.fail(new Panel.AlreadyHasParentError(a))),
      );
    }),
  );
});

describe("deleting", () => {
  it.effect("can delete single panel", () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();

      const a = yield* Panel.createNode(setTree, { dbgName: "a" });

      expect(tree.nodes[a]).toBeDefined();
      expect(Object.entries(tree.nodes)).toHaveLength(2);

      yield* Panel.deleteNode(setTree, { id: a });

      expect(tree.nodes[a]).toBeUndefined();
      expect(Object.entries(tree.nodes)).toHaveLength(1);
    }),
  );

  it.effect("can delete panel with children", () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();

      const a = yield* Panel.createNode(setTree, { dbgName: "a" });
      const b = yield* Panel.createNode(setTree, { dbgName: "b" });
      const c = yield* Panel.createNode(setTree, { dbgName: "c" });

      yield* Panel.addChild(setTree, { parentId: a, newChildId: b });
      yield* Panel.addChild(setTree, { parentId: a, newChildId: c });

      yield* Panel.deleteNode(setTree, { id: a });

      expect(tree.nodes[a]).toBeUndefined();
      expect(tree.nodes[b]).toBeUndefined();
      expect(tree.nodes[c]).toBeUndefined();
    }),
  );

  it.effect("removes from parent", () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();

      const a = yield* Panel.createNode(setTree, { dbgName: "a" });
      const b = yield* Panel.createNode(setTree, { dbgName: "b" });
      const c = yield* Panel.createNode(setTree, { dbgName: "c" });

      yield* Panel.addChild(setTree, { parentId: a, newChildId: b });
      yield* Panel.addChild(setTree, { parentId: a, newChildId: c });

      expect(tree.nodes[a].children).toContain(b);
      expect(tree.nodes[a].children).toContain(c);

      yield* Panel.deleteNode(setTree, { id: b });

      expect(tree.nodes[a].children).not.toContain(b);
      expect(tree.nodes[a].children).toContain(c);

      expect(tree.nodes[a]).toBeDefined();
      expect(tree.nodes[b]).toBeUndefined();
      expect(tree.nodes[c]).toBeDefined();
    }),
  );

  it.effect("redistributes simple", () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();

      const root = tree.root;
      const a = yield* Panel.createNode(setTree, {
        dbgName: "a",
      });
      const b = yield* Panel.createNode(setTree, {
        dbgName: "b",
        percentOfParent: Panel.Percent(0.5),
      });

      yield* Panel.addChild(setTree, { parentId: root, newChildId: a });
      yield* Panel.addChild(setTree, { parentId: root, newChildId: b });

      expect(tree.nodes[a].percentOfParent).toBe(Panel.Percent(0.75));
      expect(tree.nodes[b].percentOfParent).toBe(Panel.Percent(0.25));

      yield* Panel.deleteNode(setTree, { id: b });

      expect(tree.nodes[b]).toBeUndefined();
      expect(tree.nodes[a].percentOfParent).toBe(Panel.Percent(1));
    }),
  );

  it.effect("redistributes complex", () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();

      const root = tree.root;
      const a = yield* Panel.createNode(setTree, { dbgName: "a" });
      const b = yield* Panel.createNode(setTree, { dbgName: "b" });
      const c = yield* Panel.createNode(setTree, { dbgName: "b" });

      yield* Panel.addChild(setTree, { parentId: root, newChildId: a });
      yield* Panel.addChild(setTree, { parentId: root, newChildId: b });
      yield* Panel.addChild(setTree, { parentId: root, newChildId: c });

      // setup complex sizes
      storeUpdate(setTree, (tree) => {
        tree.nodes[a].percentOfParent = Panel.Percent(0.5);
        tree.nodes[b].percentOfParent = Panel.Percent(0.3);
        tree.nodes[c].percentOfParent = Panel.Percent(0.2);
      });

      yield* Panel.deleteNode(setTree, { id: c });

      expect(tree.nodes[c]).toBeUndefined();
      expect(tree.nodes[a].percentOfParent).toBe(Panel.Percent(0.625)); // 0.5/0.8
      expect(tree.nodes[b].percentOfParent).toBe(Panel.Percent(0.375)); // 0.3/0.8
    }),
  );

  it.effect("errors on delete root panel", () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();

      const result = yield* Effect.exit(
        Panel.deleteNode(setTree, { id: tree.root }),
      );

      expect(JSON.stringify(result)).toStrictEqual(
        JSON.stringify(Exit.fail(new Panel.CannotDeleteRootPanelError())),
      );
    }).pipe(Effect.provide(Logger.pretty)),
  );

  it.effect("errors on delete root panel (as child)", () =>
    Effect.gen(function* () {
      const [_tree, setTree] = createTreeStore();

      const a = yield* Panel.createNode(setTree, { dbgName: "a" });

      yield* storeUpdate(setTree, (tree) =>
        Effect.gen(function* () {
          const panel = yield* Panel.getNode(tree, { id: a });
          panel.children.push(tree.root);
        }),
      );

      const result = yield* Effect.exit(Panel.deleteNode(setTree, { id: a }));

      expect(JSON.stringify(result)).toStrictEqual(
        JSON.stringify(Exit.fail(new Panel.CannotDeleteRootPanelError())),
      );
    }),
  );

  it.effect("errors on delete panel with nonexistent child", () =>
    Effect.gen(function* () {
      const [tree, setTree] = createTreeStore();

      const a = yield* Panel.createNode(setTree, { dbgName: "a" });
      const b = yield* Panel.createNode(setTree, { dbgName: "b" });

      const fakeId = yield* Panel.createId;

      yield* Panel.addChild(setTree, { parentId: a, newChildId: b });

      yield* storeUpdate(setTree, (tree) =>
        Effect.gen(function* () {
          const panel = yield* Panel.getNode(tree, { id: a });
          panel.children.push(fakeId);
        }),
      );

      expect(tree.nodes[a]).toBeDefined();
      expect(tree.nodes[a].children).toHaveLength(2);
      expect(Object.entries(tree.nodes)).toHaveLength(3);

      const result = yield* Effect.exit(Panel.deleteNode(setTree, { id: a }));

      expect(JSON.stringify(result)).toStrictEqual(
        JSON.stringify(
          Exit.fail(new Panel.PanelDoesNotExistError(fakeId).withParent(a)),
        ),
      );

      expect(tree.nodes[a]).toBeDefined();
      expect(tree.nodes[a].children).toHaveLength(2);
      expect(Object.entries(tree.nodes)).toHaveLength(3);
    }).pipe(Effect.provide(Logger.pretty)),
  );
});
