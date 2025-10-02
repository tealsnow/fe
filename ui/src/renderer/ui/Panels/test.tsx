import { batch, Component, onMount } from "solid-js";

import Percent from "~/lib/Percent";
import Integer from "~/lib/Integer";

import * as Panels from "./index";

export const Test: Component<{}> = () => {
  return (
    <Panels.Context.Provider>
      <ActualTest />
    </Panels.Context.Provider>
  );
};

const ActualTest: Component = () => {
  const ctx = Panels.useContext();

  onMount(() => {
    batch(() => {
      ctx.setWorkspace({
        root: Panels.PanelNode.makeTabs({
          active: Integer(0),
          children: [
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
            ctx.createLeaf(),
          ],
        }),
        sidebars: {
          left: Panels.WorkspaceSidebar({
            size: Percent.from(15),
            enabled: true,
            node: Panels.PanelNode.makeTabs({
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
          right: Panels.WorkspaceSidebar({
            size: Percent.from(35),
            enabled: true,
            node: Panels.PanelNode.makeSplit({
              axis: "vertical",
              children: [
                Panels.PanelNode.makeTabs({
                  children: [
                    ctx.createLeaf({
                      title: "right top",
                      render: () => <>right top content</>,
                    }),
                  ],
                }),
                Panels.PanelNode.makeTabs({
                  children: [
                    ctx.createLeaf({
                      title: "wow",
                      render: () => <></>,
                    }),
                  ],
                }),
                Panels.PanelNode.makeSplit({
                  axis: "horizontal",
                  children: [
                    Panels.PanelNode.makeTabs({
                      children: [
                        ctx.createLeaf({
                          title: "right bottom left",
                          render: () => <>right bottom left content</>,
                        }),
                      ],
                    }),
                    Panels.PanelNode.makeTabs({
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
          bottom: Panels.WorkspaceSidebar({
            enabled: false,
            node: Panels.PanelNode.makeTabs(),
          }),
        },
      });
    });
  });

  return <Panels.View.Root />;
};
