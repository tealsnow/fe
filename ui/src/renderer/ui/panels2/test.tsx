import { batch, Component, Show } from "solid-js";

import { Console, Effect } from "effect";

import Button from "~/ui/components/Button";
import assert from "~/lib/assert";

import Panel from "./Panel";
import Render from "./Render";

export const Test: Component<{}> = () => {
  return (
    <Panel.ContextProvider>
      <ActualTest />
    </Panel.ContextProvider>
  );
};

const ActualTest: Component<{}> = () => {
  const ctx = Panel.useContext();
  const tree = ctx.tree;

  const TestBtn: Component<{ name: string; onClick: () => void }> = (props) => {
    return (
      <Button
        onClick={() => {
          console.group(props.name);
          props.onClick();
          console.groupEnd();
        }}
      >
        {props.name}
      </Button>
    );
  };

  const emptyContent = (): Panel.Node.Leaf["content"] => async () => ({
    default: () => <></>,
  });

  const root = ctx.getRoot();

  const testPanel = Panel.Node.Leaf({
    title: () => "test",
    content: async () => ({
      default: () => {
        return <>hi</>;
      },
    }),
  });

  ctx.addNode(testPanel);
  ctx.addChild({ dockSpace: root.id, child: testPanel.id }).pipe(
    Effect.tapError((err) => Console.error(err)),
    Effect.runSync,
  );

  return (
    <div class="flex flex-row grow overflow-hidden">
      <Render.DockSpaceSlotted slotted={() => root.layout} />

      <Show when={ctx.showDebugSidePanel()}>
        <div class="flex flex-col w-1/3 gap-2 p-2 overflow-auto border-theme-border border-l">
          <TestBtn
            name="add single node"
            onClick={() => {
              ctx.addNode(
                Panel.Node.Leaf({
                  title: () => "test",
                  content: emptyContent(),
                }),
              );
            }}
          />

          <TestBtn
            name="add two items to map"
            onClick={() => {
              ctx.addNode(
                Panel.Node.Leaf({
                  title: () => "test1",
                  content: emptyContent(),
                }),
              );
              ctx.addNode(
                Panel.Node.Leaf({
                  title: () => "test2",
                  content: emptyContent(),
                }),
              );
            }}
          />

          <TestBtn
            name="add two items to map (batched)"
            onClick={() => {
              ctx.addNodes(
                Panel.Node.Leaf({
                  title: () => "test1",
                  content: emptyContent(),
                }),
                Panel.Node.Leaf({
                  title: () => "test2",
                  content: emptyContent(),
                }),
              );
            }}
          />

          <TestBtn
            name="change root to vertical split"
            onClick={() => {
              tree.setNodes(tree.root.uuid, (node) => {
                assert(Panel.Node.$is("DockSpace")(node));
                return {
                  ...node,
                  layout: Panel.Node.DockSpaceLayout.Split({
                    direction: "vertical",
                  }),
                };
              });
            }}
          />

          <TestBtn
            name="add leaf child to root"
            onClick={() => {
              batch(() => {
                const leaf = ctx.addNode(
                  Panel.Node.Leaf({
                    title: () => "some leaf",
                    content: emptyContent(),
                  }),
                );

                ctx.addChild({ dockSpace: root.id, child: leaf.id }).pipe(
                  Effect.catchAll((error) => {
                    console.error("Failure to add child: ", error);
                    return Effect.void;
                  }),
                  Effect.runSync,
                );
              });
            }}
          />

          <TestBtn
            name="undo"
            onClick={() => {
              ctx.undo();
            }}
          />
          <TestBtn
            name="redo"
            onClick={() => {
              ctx.redo();
            }}
          />
        </div>
      </Show>
    </div>
  );
};
