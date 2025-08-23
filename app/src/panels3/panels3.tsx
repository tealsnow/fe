// import { Emitter } from "solid-events";
// import { v4 as uuidv4 } from "uuid";
// import { produceUpdate, StoreObjectProduce } from "../SignalObject";

import { Console, Effect, Match, Option, pipe } from "effect";

import * as Panel from "./Panel";
import { produceUpdate, storeObjectProduceFromStore } from "../SignalObject";
import { createStore } from "solid-js/store";
import { notify } from "../notifications";
import { createSignal, onMount, Show } from "solid-js";
import Inspector from "./Inspector";
import clsx from "clsx";

const Panels3 = () => {
  const treeStore = storeObjectProduceFromStore(
    createStore<Panel.PanelTreeData>(Panel.createTree.pipe(Effect.runSync)),
  );

  const [selectedId, setSelectedId] = createSignal<
    Option.Option<Panel.PanelId>
  >(Option.some(treeStore.value.root));

  const [showExplorer, setShowExplorer] = createSignal(true);

  onMount(() => {
    // console.log("Running Panel3 OnMount\n\n\n\n");
    Effect.gen(function* () {
      const root = treeStore.value.root;

      const a = yield* Panel.createPanel(treeStore, {
        dbgName: "a",
        layout: "vertical",
      });
      const b = yield* Panel.createPanel(treeStore, { dbgName: "b" });
      const c = yield* Panel.createPanel(treeStore, { dbgName: "c" });
      const d = yield* Panel.createPanel(treeStore, {
        dbgName: "d",
        layout: "vertical",
      });

      yield* Panel.addChild(treeStore, { parentId: root, newChildId: a });
      yield* Panel.addChild(treeStore, { parentId: root, newChildId: d });

      yield* Panel.addChild(treeStore, { parentId: a, newChildId: b });
      yield* Panel.addChild(treeStore, { parentId: a, newChildId: c });

      // const id1 = yield* Panel.createId;
      // // const id2 = yield* Panel.createId;
      // // const id3 = yield* Panel.createId;
      // // [id1, id2, id3].map(console.log);
      // const a = yield* Panel.createPanel(treeStore, { dbgName: "a" });
      // const b = yield* Panel.createPanel(treeStore, { dbgName: "b" });
      // const c = yield* Panel.createPanel(treeStore, { dbgName: "c" });
      // // const ids = [a, b, c, id1];
      // const ids = [a, b, c];
      // console.log("listing panels");
      // yield* Effect.forEach(ids, (id) =>
      //   Panel.getPanel(treeStore.value, { panelId: id }).pipe(
      //     Effect.matchEffect({
      //       onFailure: Console.error,
      //       onSuccess: (panel) =>
      //         Effect.succeed(
      //           `panel: id '${panel.id}', dbgName: '${panel.dbgName}'`,
      //         ).pipe(Effect.tap(Console.log)),
      //     }),
      //   ),
      // );
      // // [a, b, c].map(console.log);
      // produceUpdate(treeStore, (tree) => {
      //   const aPanel = tree.nodes[a];
      //   aPanel.children.push(id1);
      //   aPanel.children.push(tree.root);
      //   console.log(aPanel);
      // });
      // console.log(`root id: ${treeStore.value.root}`);
      // console.log(`id1: ${id1}`);
      // const fallible = fallibleEffect(true);
      // yield* fallible.pipe(
      //   Effect.matchEffect({
      //     onFailure: (error) => {
      //       console.error(error);
      //       return Effect.void;
      //     },
      //     onSuccess: () => Console.log("fallible effect succeeded"),
      //   }),
      // );
      // logScope("list before delete", () => {
      //   printAllPanels(treeStore.value).pipe(Effect.runSync);
      // });
      // yield* Panel.deletePanel(treeStore, { panelId: id1 }).pipe(
      //   Effect.matchEffect({
      //     onFailure: (error) => {
      //       console.error(error);
      //       return Effect.void;
      //     },
      //     onSuccess: () => Console.log("panel deleted successfully"),
      //   }),
      // );
      // logScope("list after delete", () => {
      //   printAllPanels(treeStore.value).pipe(Effect.runSync);
      // });
    }).pipe(Effect.runSync);
  });

  return (
    <div class="flex w-full h-full">
      <div
        class={clsx(
          "h-full border-r border-theme-border p-0.5",
          showExplorer() ? "w-[50%]" : "w-full",
        )}
      >
        {/*<RenderPanels
          treeStore={treeStore}
          root={root}
          selectedId={selectedId()}
          emitEvent={emitEvent}
        />*/}
      </div>

      <Show when={showExplorer()}>
        <div class="w-[50%]">
          <Inspector
            treeStore={treeStore}
            selectedId={selectedId()}
            selectPanel={setSelectedId}
          />
        </div>
      </Show>
    </div>
  );
};

// const fallibleEffect = (fail: boolean): Effect.Effect<void, string> => {
//   if (fail) return Effect.fail("failed");
//   return Effect.succeed(void {});
// };

// const printAllPanels = (tree: Panel.PanelTreeData) =>
//   Effect.forEach(Object.entries(tree.nodes), ([_id, node]) => {
//     console.log(`node id: ${node.id}, dbgName: ${node.dbgName}`);
//     return Effect.void;
//   });

// const logScope = (name: string, fn: () => void) => {
//   console.log(`\n> --- ${name} ---`);
//   fn();
//   console.log(`< --- ${name} ---\n\n`);
// };

export default Panels3;
