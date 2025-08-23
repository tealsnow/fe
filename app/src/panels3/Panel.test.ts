import { it, expect, describe } from "@effect/vitest";
import { Effect, Exit, Logger, Option } from "effect";

import { produceUpdate, storeObjectProduceFromStore } from "../SignalObject";
import { createStore } from "solid-js/store";

import * as Panel from "./Panel";

const createTreeStore = () => {
  return storeObjectProduceFromStore(
    createStore<Panel.PanelTreeData>(Panel.createTree.pipe(Effect.runSync)),
  );
};

it.effect("errors on get nonexistent panel", () =>
  Effect.gen(function* () {
    const treeStore = createTreeStore();

    const id = yield* Panel.createId;
    const result = yield* Effect.exit(
      Panel.getPanel(treeStore.value, { panelId: id }),
    );

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
      const treeStore = createTreeStore();

      expect(Object.entries(treeStore.value.nodes)).toHaveLength(1);

      const a = yield* Panel.createPanel(treeStore, { dbgName: "a" });
      const b = yield* Panel.createPanel(treeStore, { dbgName: "b" });
      const c = yield* Panel.createPanel(treeStore, { dbgName: "c" });

      expect(Object.entries(treeStore.value.nodes)).toHaveLength(4);

      const ids = [a, b, c];
      const names = ["a", "b", "c"];

      const zipped: [Panel.PanelId, string][] = ids.map((id, idx) => [
        id,
        names[idx],
      ]);
      yield* Effect.forEach(zipped, ([id, name]) =>
        Effect.gen(function* () {
          const panel = yield* Panel.getPanel(treeStore.value, { panelId: id });
          expect(panel).toBeDefined();
          expect(panel.dbgName).toBe(name);
          return Effect.void;
        }),
      );
    }).pipe(Effect.provide(Logger.pretty)),
  );

  it.effect("can add child", () =>
    Effect.gen(function* () {
      const treeStore = createTreeStore();

      const root = treeStore.value.root;
      const a = yield* Panel.createPanel(treeStore, { dbgName: "a" });

      const rootPanel = yield* Panel.getPanel(treeStore.value, {
        panelId: root,
      });

      expect(rootPanel.children).toHaveLength(0);

      yield* Panel.addChild(treeStore, { parentId: root, newChildId: a });

      expect(rootPanel.children).toHaveLength(1);
      expect(rootPanel.children).toContain(a);

      const aPanel = yield* Panel.getPanel(treeStore.value, {
        panelId: a,
      });

      expect(aPanel.parent).toStrictEqual(Option.some(root));
      expect(aPanel.percentOfParent).toBe(1);
    }),
  );

  it.effect("can add children", () =>
    Effect.gen(function* () {
      const treeStore = createTreeStore();

      const root = treeStore.value.root;
      const a = yield* Panel.createPanel(treeStore, { dbgName: "a" });
      const b = yield* Panel.createPanel(treeStore, { dbgName: "b" });

      const rootPanel = yield* Panel.getPanel(treeStore.value, {
        panelId: root,
      });

      expect(rootPanel.children).toHaveLength(0);

      yield* Panel.addChild(treeStore, { parentId: root, newChildId: a });
      yield* Panel.addChild(treeStore, { parentId: root, newChildId: b });

      const aPanel = yield* Panel.getPanel(treeStore.value, {
        panelId: a,
      });
      const bPanel = yield* Panel.getPanel(treeStore.value, {
        panelId: b,
      });

      const childrenValid = yield* Panel.validateChildrenSizes(
        treeStore.value,
        { panelId: root },
      );
      expect(childrenValid).toStrictEqual({ ok: true, difference: 0 });

      expect(aPanel.parent).toStrictEqual(Option.some(root));
      expect(aPanel.percentOfParent).toBe(0.5);
      expect(bPanel.parent).toStrictEqual(Option.some(root));
      expect(bPanel.percentOfParent).toBe(0.5);
    }),
  );

  it.effect("can add children while keeping ratio", () =>
    Effect.gen(function* () {
      const treeStore = createTreeStore();

      const root = treeStore.value.root;
      const a = yield* Panel.createPanel(treeStore, {
        dbgName: "a",
        percentOfParent: Panel.Percent(1),
      });
      const b = yield* Panel.createPanel(treeStore, {
        dbgName: "b",
        percentOfParent: Panel.Percent(0.5),
      });

      const rootPanel = yield* Panel.getPanel(treeStore.value, {
        panelId: root,
      });

      expect(rootPanel.children).toHaveLength(0);

      yield* Panel.addChild(treeStore, { parentId: root, newChildId: a });
      yield* Panel.addChild(treeStore, { parentId: root, newChildId: b });

      const aPanel = yield* Panel.getPanel(treeStore.value, {
        panelId: a,
      });
      const bPanel = yield* Panel.getPanel(treeStore.value, {
        panelId: b,
      });

      const childrenValid = yield* Panel.validateChildrenSizes(
        treeStore.value,
        { panelId: root },
      );
      expect(childrenValid).toStrictEqual({ ok: true, difference: 0 });

      expect(aPanel.parent).toStrictEqual(Option.some(root));
      expect(aPanel.percentOfParent).toBe(0.75);
      expect(bPanel.parent).toStrictEqual(Option.some(root));
      expect(bPanel.percentOfParent).toBe(0.25);
    }),
  );

  it.effect("errors when parent does not exist", () =>
    Effect.gen(function* () {
      const treeStore = createTreeStore();

      const fakeParent = yield* Panel.createId;

      const a = yield* Panel.createPanel(treeStore, { dbgName: "a" });

      expect(treeStore.value.nodes[a]).toBeDefined();
      expect(Object.entries(treeStore.value.nodes)).toHaveLength(2);

      const result = yield* Effect.exit(
        Panel.addChild(treeStore, { parentId: fakeParent, newChildId: a }),
      );

      expect(JSON.stringify(result)).toStrictEqual(
        JSON.stringify(Exit.fail(new Panel.PanelDoesNotExistError(fakeParent))),
      );
    }),
  );

  it.effect("errors when child does not exist", () =>
    Effect.gen(function* () {
      const treeStore = createTreeStore();

      const a = yield* Panel.createPanel(treeStore, { dbgName: "a" });

      const fakeChild = yield* Panel.createId;

      expect(treeStore.value.nodes[a]).toBeDefined();
      expect(Object.entries(treeStore.value.nodes)).toHaveLength(2);

      const result = yield* Effect.exit(
        Panel.addChild(treeStore, { parentId: a, newChildId: fakeChild }),
      );

      expect(JSON.stringify(result)).toStrictEqual(
        JSON.stringify(Exit.fail(new Panel.PanelDoesNotExistError(fakeChild))),
      );
    }),
  );

  it.effect("errors when there is an existing parent", () =>
    Effect.gen(function* () {
      const treeStore = createTreeStore();

      const parentA = yield* Panel.createPanel(treeStore, {
        dbgName: "parentA",
      });
      const parentB = yield* Panel.createPanel(treeStore, {
        dbgName: "parentB",
      });
      const a = yield* Panel.createPanel(treeStore, { dbgName: "a" });

      yield* Panel.addChild(treeStore, { parentId: parentA, newChildId: a });

      const result = yield* Effect.exit(
        Panel.addChild(treeStore, { parentId: parentB, newChildId: a }),
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
      const treeStore = createTreeStore();

      const a = yield* Panel.createPanel(treeStore, { dbgName: "a" });

      expect(treeStore.value.nodes[a]).toBeDefined();
      expect(Object.entries(treeStore.value.nodes)).toHaveLength(2);

      yield* Panel.deletePanel(treeStore, { panelId: a });

      expect(treeStore.value.nodes[a]).toBeUndefined();
      expect(Object.entries(treeStore.value.nodes)).toHaveLength(1);
    }),
  );

  it.effect("can delete panel with children", () =>
    Effect.gen(function* () {
      const treeStore = createTreeStore();

      const a = yield* Panel.createPanel(treeStore, { dbgName: "a" });
      const b = yield* Panel.createPanel(treeStore, { dbgName: "b" });
      const c = yield* Panel.createPanel(treeStore, { dbgName: "c" });

      // @TODO: Use Panel.addChild
      yield* produceUpdate(treeStore, (tree) =>
        Effect.gen(function* () {
          const panel = yield* Panel.getPanel(tree, { panelId: a });
          panel.children.push(b);
          panel.children.push(c);

          // console.debug(panel);
        }),
      );

      yield* Panel.deletePanel(treeStore, { panelId: a });

      expect(treeStore.value.nodes[a]).toBeUndefined();
      expect(treeStore.value.nodes[b]).toBeUndefined();
      expect(treeStore.value.nodes[c]).toBeUndefined();
    }),
  );

  it.effect("errors on delete root panel", () =>
    Effect.gen(function* () {
      const treeStore = createTreeStore();

      const result = yield* Effect.exit(
        Panel.deletePanel(treeStore, { panelId: treeStore.value.root }),
      );

      expect(JSON.stringify(result)).toStrictEqual(
        JSON.stringify(Exit.fail(new Panel.CannotDeleteRootPanelError())),
      );
    }).pipe(Effect.provide(Logger.pretty)),
  );

  it.effect("errors on delete root panel (as child)", () =>
    Effect.gen(function* () {
      const treeStore = createTreeStore();

      const a = yield* Panel.createPanel(treeStore, { dbgName: "a" });

      yield* produceUpdate(treeStore, (tree) =>
        Effect.gen(function* () {
          const panel = yield* Panel.getPanel(tree, { panelId: a });
          panel.children.push(treeStore.value.root);

          // console.debug(panel);
        }),
      );

      const result = yield* Effect.exit(
        Panel.deletePanel(treeStore, { panelId: a }),
      );

      expect(JSON.stringify(result)).toStrictEqual(
        JSON.stringify(Exit.fail(new Panel.CannotDeleteRootPanelError())),
      );
    }).pipe(Effect.provide(Logger.pretty)),
  );

  it.effect("errors on delete panel with nonexistent child", () =>
    Effect.gen(function* () {
      const treeStore = createTreeStore();

      const a = yield* Panel.createPanel(treeStore, { dbgName: "a" });
      const b = yield* Panel.createPanel(treeStore, { dbgName: "b" });

      const fakeId = yield* Panel.createId;

      yield* produceUpdate(treeStore, (tree) =>
        Effect.gen(function* () {
          const panel = yield* Panel.getPanel(tree, { panelId: a });
          // @TODO: use addChild for this one only
          panel.children.push(b);
          panel.children.push(fakeId);
        }),
      );

      expect(treeStore.value.nodes[a]).toBeDefined();
      expect(treeStore.value.nodes[a].children).toHaveLength(2);
      expect(Object.entries(treeStore.value.nodes)).toHaveLength(3);

      const result = yield* Effect.exit(
        Panel.deletePanel(treeStore, { panelId: a }),
      );

      expect(JSON.stringify(result)).toStrictEqual(
        JSON.stringify(
          Exit.fail(new Panel.PanelDoesNotExistError(fakeId).withParent(a)),
        ),
      );

      expect(treeStore.value.nodes[a]).toBeDefined();
      expect(treeStore.value.nodes[a].children).toHaveLength(2);
      expect(Object.entries(treeStore.value.nodes)).toHaveLength(3);
    }).pipe(Effect.provide(Logger.pretty)),
  );
});
