import { Component, createSignal, For, Show } from "solid-js";
import { makePersisted } from "@solid-primitives/storage";

import { Effect } from "effect";

import { cn } from "~/lib/cn";
import effectEdgeRunSync from "~/lib/effectEdgeRunSync";

import * as Panel from "./Panel";
import Inspector from "./Inspector";
import { RenderPanels } from "./render";
import { usePanelContext } from "./PanelContext";

export const setupDebugPanels = (): void => {
  const { tree, setTree } = usePanelContext();

  Effect.gen(function* () {
    const root = tree.root;

    const a = yield* Panel.Node.Parent.create(setTree, {
      layout: Panel.Layout.Split({ direction: "vertical" }),
    });

    const b = yield* Panel.Node.Leaf.create(setTree, { title: "b" });
    const c = yield* Panel.Node.Parent.create(setTree, {
      layout: Panel.Layout.Tabs(),
    });
    const d = yield* Panel.Node.Parent.create(setTree, {
      layout: Panel.Layout.Split({ direction: "horizontal" }),
    });
    const e = yield* Panel.Node.Parent.create(setTree, {
      layout: Panel.Layout.Tabs(),
    });
    const f = yield* Panel.Node.Leaf.create(setTree, { title: "f" });
    const g = yield* Panel.Node.Parent.create(setTree, {
      layout: Panel.Layout.Split({ direction: "vertical" }),
    });

    yield* Panel.Node.Parent.addChild(setTree, {
      parentId: d,
      childId: f,
    });
    yield* Panel.Node.Parent.addChild(setTree, {
      parentId: d,
      childId: g,
    });

    const p = yield* Panel.Node.Leaf.create(setTree, {
      title: "p",
    });
    const q = yield* Panel.Node.Leaf.create(setTree, { title: "q" });
    const r = yield* Panel.Node.Leaf.create(setTree, { title: "r" });
    const s = yield* Panel.Node.Leaf.create(setTree, { title: "s" });
    const t = yield* Panel.Node.Leaf.create(setTree, { title: "t" });

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

    yield* Panel.Node.Parent.addChild(setTree, { parentId: e, childId: p });
    yield* Panel.Node.Parent.addChild(setTree, { parentId: e, childId: q });
    yield* Panel.Node.Parent.addChild(setTree, { parentId: e, childId: r });

    yield* Panel.Node.Parent.addChild(setTree, { parentId: c, childId: s });
    yield* Panel.Node.Parent.addChild(setTree, { parentId: c, childId: t });
  }).pipe(effectEdgeRunSync);
};

export const PanelsRoot: Component = () => {
  // false positive
  // eslint-disable-next-line solid/reactivity
  const [showExplorer, setShowExplorer] = makePersisted(createSignal(false), {
    name: "show-panel-explorer",
    storage: sessionStorage,
  });

  // onMount(() => {
  //   setupDebugPanels();
  // });

  return (
    <div class="flex flex-col w-full h-full">
      <Show when={false}>
        <div class="flex flex-row h-8 border-b border-theme-border items-center p-2">
          <div class="ml-auto flex flex-row gap-2">
            <For
              each={[
                {
                  get: showExplorer,
                  set: setShowExplorer,
                  lbl: "show explorer",
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
      </Show>

      <div class="flex h-full w-full">
        <div
          class={cn(
            "h-full border-theme-border",
            showExplorer() ? "border-r w-[60%]" : "w-full",
          )}
        >
          <RenderPanels />
        </div>

        <Show when={showExplorer()}>
          <div class="w-[40%]">
            <Inspector />
          </div>
        </Show>
      </div>
    </div>
  );
};

export default PanelsRoot;
