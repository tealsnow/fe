import { batch, Component, onMount } from "solid-js";

import Percent from "~/lib/Percent";
import Integer from "~/lib/Integer";

import { PanelNode, WorkspaceSidebar } from "./data";
import { PanelContextProvider, usePanelContext } from "./ContextProvider";
import View from "./View";

export const Test: Component<{}> = () => {
  return (
    <PanelContextProvider>
      <ActualTest />
    </PanelContextProvider>
  );
};

const ActualTest: Component = () => {
  const ctx = usePanelContext();

  onMount(() => {
    batch(() => {
      ctx.setWorkspace({
        root: PanelNode.makeTabs({
          active: Integer(0),
          children: [
            ctx.createLeaf({
              title: "right split dbg",
              render: () => {
                const rightSplit = ctx.workspace.sidebars.right.node;
                return (
                  <div class="flex flex-col p-1">
                    <pre>{JSON.stringify(rightSplit, null, 2)}</pre>
                  </div>
                );
              },
            }),
            ctx.createLeaf({
              title: "workspace dbg",
              render: () => {
                return (
                  <div class="flex flex-col p-1">
                    <pre>{JSON.stringify(ctx.workspace, null, 2)}</pre>
                  </div>
                );
              },
            }),
            ctx.createLeaf(),
          ],
        }),
        sidebars: {
          left: WorkspaceSidebar({
            size: Percent.from(15),
            enabled: true,
            node: PanelNode.makeTabs({
              children: [
                ctx.createLeaf({
                  title: "foo",
                  render: () => <>foo content</>,
                }),
                ctx.createLeaf({
                  title: "bar",
                  render: () => <>bar content</>,
                }),
                ctx.createLeaf({
                  title: "long tab name",
                  render: () => <>content</>,
                }),
              ],
            }),
          }),
          right: WorkspaceSidebar({
            size: Percent.from(35),
            enabled: true,
            node: PanelNode.makeSplit({
              axis: "vertical",
              children: [
                PanelNode.makeTabs({
                  children: [
                    ctx.createLeaf({
                      title: "right top",
                      render: () => <>right top content</>,
                    }),
                  ],
                }),
                PanelNode.makeTabs({
                  children: [
                    ctx.createLeaf({
                      title: "wow",
                      render: () => <></>,
                    }),
                  ],
                }),
                PanelNode.makeSplit({
                  axis: "horizontal",
                  children: [
                    PanelNode.makeTabs({
                      children: [
                        ctx.createLeaf({
                          title: "right bottom left",
                          render: () => <>right bottom left content</>,
                        }),
                      ],
                    }),
                    PanelNode.makeTabs({
                      children: [
                        ctx.createLeaf({
                          title: "tab 1",
                          render: () => <></>,
                        }),
                        ctx.createLeaf({
                          title: "tab 2",
                          render: () => <></>,
                        }),
                      ],
                    }),
                  ],
                }),
              ],
            }),
          }),
          bottom: WorkspaceSidebar({
            enabled: false,
            node: PanelNode.makeTabs(),
          }),
        },
      });
    });
  });

  return <View.Root />;
};
