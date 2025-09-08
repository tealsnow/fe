import { createStore } from "solid-js/store";
import { createSignal, For, onMount, Show } from "solid-js";
import { makePersisted } from "@solid-primitives/storage";

import { Effect, Option } from "effect";

import { cn } from "~/lib/cn";

import * as Panel from "./Panel";
import Inspector from "./Inspector";
import { RenderPanels } from "./render";

export const Panels3 = () => {
  const [tree, setTree] = createStore<Panel.Tree>(
    Panel.Tree.create.pipe(Effect.runSync),
  );

  const [selectedId, setSelectedId] = createSignal<Option.Option<Panel.ID>>(
    // Option.some(tree.root),
    Option.none(),
  );

  const [showExplorer, setShowExplorer] = makePersisted(createSignal(true), {
    name: "show-panel-explorer",
    storage: sessionStorage,
  });

  const [showDbgHeader, setShowDbgHeader] = makePersisted(createSignal(true), {
    name: "show-panel-debug-header",
    storage: sessionStorage,
  });

  onMount(() => {
    Effect.gen(function* () {
      const root = tree.root;
      console.log("tree:", tree);

      const a = yield* Panel.Node.Parent.create(setTree, {
        layout: "vertical",
      });

      const b = yield* Panel.Node.Leaf.create(setTree, { title: "b" });
      const c = yield* Panel.Node.Leaf.create(setTree, { title: "c" });
      const d = yield* Panel.Node.Leaf.create(setTree, { title: "d" });
      const e = yield* Panel.Node.Leaf.create(setTree, { title: "e" });

      yield* Panel.Node.Parent.addChild(setTree, {
        parentId: root,
        childId: a,
      });

      yield* Panel.Node.Parent.addChild(setTree, {
        parentId: root,
        childId: e,
      });

      yield* Panel.Node.Parent.addChild(setTree, { parentId: a, childId: b });
      yield* Panel.Node.Parent.addChild(setTree, { parentId: a, childId: c });
      yield* Panel.Node.Parent.addChild(setTree, { parentId: a, childId: d });
    }).pipe(Effect.runSync);
  });

  return (
    <div class="flex flex-col w-full h-full">
      <div class="flex flex-row h-8 border-b border-theme-border items-center p-2">
        <div class="ml-auto flex flex-row gap-2">
          <For
            each={[
              {
                get: showExplorer,
                set: setShowExplorer,
                lbl: "show explorer",
              },
              {
                get: showDbgHeader,
                set: setShowDbgHeader,
                lbl: "show debug header",
              },
            ]}
          >
            {({ get, set, lbl }) => (
              <label class="flex flex-row gap-1">
                <input
                  type="checkbox"
                  checked={get()}
                  id={lbl}
                  class="form-checkbox border-1 border-theme-colors-purple-border
                  bg-theme-colors-purple-background outline-0
                  checked:bg-theme-colors-purple-base ring-offset-0 ring-0"
                  onChange={({ target: { checked } }) => set(checked)}
                />
                {lbl}
              </label>
            )}
          </For>
        </div>
      </div>

      <div class="flex h-full w-full">
        <div
          class={cn(
            "h-full border-r border-theme-border",
            showExplorer() ? "w-[60%]" : "w-full",
          )}
        >
          <RenderPanels
            tree={tree}
            setTree={setTree}
            selectedPanel={selectedId}
            selectPanel={(id) => setSelectedId(Option.some(id))}
            dbgHeader={showDbgHeader}
          />
        </div>

        <Show when={showExplorer()}>
          <div class="w-[40%]">
            <Inspector
              tree={tree}
              setTree={setTree}
              selectedId={selectedId}
              setSelectedId={setSelectedId}
            />
          </div>
        </Show>
      </div>
    </div>
  );
};

export default Panels3;
