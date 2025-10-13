import { createSignal, onCleanup, onMount, Component, For } from "solid-js";

import { Effect, Option } from "effect";

import { cn } from "~/lib/cn";
import Integer from "~/lib/Integer";
import * as Notif from "~/lib/Notif";

import Icon from "~/ui/components/Icon";
import Noise from "~/ui/components/Noise";

import * as Theme from "~/ui/Theme";
import * as StatusBar from "~/ui/StatusBar";
import * as Window from "~/ui/Window";
import * as Panels from "~/ui/Panels";

import Dbg from "~/Dbg";

import NodeGraph from "~/NodeGraph";
import CommandPaletteTest from "~/CommandPaletteTest";
import TextEditingTest from "~/TextEditingTest";

export const App: Component = () => {
  return (
    <Window.Provider>
      <AfterWindow />
    </Window.Provider>
  );
};

const AfterWindow: Component = () => {
  // @NOTE: This applies the theme globally - setting the css vars on the
  //  document globally. This is mostly just for the toasts, since they
  //  are built with normal css.
  //  If that changes to use inline styles and/or tailwind we can remove this
  //
  //  As is stands this works just fine, if and when we do a theme preview
  //  we can just use the provider, unless we want to show what toasts would
  //  look like...
  Theme.applyThemeColors(Theme.defaultTheme.colors);

  const windowCtx = Window.useContext();

  return (
    <Theme.Provider
      theme={Theme.defaultTheme}
      class="flex w-screen h-screen"
      applyRounding={!windowCtx.maximized()}
    >
      <Notif.Provider>
        <StatusBar.Provider>
          <Panels.Context.Provider>
            <Root />
          </Panels.Context.Provider>
        </StatusBar.Provider>
      </Notif.Provider>
    </Theme.Provider>
  );
};

const Root: Component = () => {
  const [showNoise, setShowNoise] = createSignal(true);

  const windowCtx = Window.useContext();
  const themeCtx = Theme.useContext();
  const statusBarCtx = StatusBar.useContext();
  const panelCtx = Panels.useContext();
  const notifCtx = Notif.useContext();

  onMount(() => {
    panelCtx.setWorkspace((workspace) =>
      Panels.Workspace({
        ...workspace,
        root: Panels.PanelNode.makeTabs({
          active: Integer(0),
          children: [
            panelCtx.createLeaf({
              title: "node graph",
              tooltip: "node graph test",
              render: () => <NodeGraph />,
            }),
            panelCtx.createLeaf({
              title: "text editing",
              tooltip: "text editing test",
              render: () => <TextEditingTest />,
            }),
            panelCtx.createLeaf({
              title: "command palette",
              tooltip: "command palette test",
              render: () => <CommandPaletteTest />,
            }),
            panelCtx.createLeaf({
              title: "dbg",
              tooltip: "testing stuff",
              render: () => <Dbg setShowNoise={setShowNoise} />,
            }),
            panelCtx.createLeaf({
              title: "theme showcase",
              tooltip: "showcase all aspects of the current theme",
              render: () => <Theme.Showcase />,
            }),
          ],
        }),
        sidebars: Panels.WorkspaceSidebars({
          left: Panels.WorkspaceSidebar({
            enabled: false,
            node: Panels.PanelNode.makeTabs(),
          }),
          right: Panels.WorkspaceSidebar({
            enabled: false,
            node: Panels.PanelNode.makeTabs(),
          }),
          bottom: Panels.WorkspaceSidebar({
            enabled: false,
            node: Panels.PanelNode.makeTabs(),
          }),
        }),
      }),
    );

    const notificationPanelId = panelCtx.createLeaf({
      title: "notifications",
      tooltip: "notifications",
      render: () => (
        <div class="w-full h-full p-2 flex flex-col gap-1">
          <For each={notifCtx.notifications}>
            {(entry) => (
              <div class="border p-2 rounded-md">{entry.content}</div>
            )}
          </For>
        </div>
      ),
    });

    const [cleanup, _id] = statusBarCtx.addItem({
      alignment: "right",
      item: StatusBar.BarItem.iconButton({
        icon: () => <Icon icon="Bell" />,
        tooltip: () => "notifications",
        onClick: () => {
          const sidebars = panelCtx.workspace.sidebars;

          if (Panels.PanelNode.$is("Tabs")(sidebars.right.node)) {
            // right is tabs

            const notifPanelIdx = sidebars.right.node.children.findIndex(
              (child) => child.id === notificationPanelId.id,
            );
            if (notifPanelIdx !== -1) {
              // notif panel is in right
              if (
                !sidebars.right.node.active.pipe(
                  Option.map((idx) => idx === notifPanelIdx),
                  Option.getOrElse(() => false),
                )
              )
                // notif panel is not active
                panelCtx.setWorkspace("sidebars", (sidebars) =>
                  Panels.WorkspaceSidebars({
                    ...sidebars,
                    right: Panels.WorkspaceSidebar({
                      ...sidebars.right,
                      // @ts-expect-error 2345
                      node: Panels.PanelNode.Tabs({
                        ...sidebars.right.node,
                        active: Option.some(Integer(notifPanelIdx)),
                      }),
                    }),
                  }),
                );
            } else {
              // notif panel is not in right
              panelCtx.setWorkspace("sidebars", (sidebars) =>
                Panels.WorkspaceSidebars({
                  ...sidebars,
                  right: Panels.WorkspaceSidebar({
                    ...sidebars.right,
                    node: Panels.tabsAddTab({
                      // @ts-expect-error 2322
                      tabs: sidebars.right.node,
                      newLeaf: notificationPanelId,
                    }).pipe(Effect.runSync),
                  }),
                }),
              );
            }

            if (!sidebars.right.enabled)
              // notif panel is not enabled
              panelCtx.setWorkspace("sidebars", (sidebars) =>
                Panels.WorkspaceSidebars({
                  ...sidebars,
                  right: Panels.WorkspaceSidebar({
                    ...sidebars.right,
                    enabled: true,
                  }),
                }),
              );
          } else {
            console.warn("TODO: right sidebar is not tabs");
          }
        },
      }),
    });
    onCleanup(() => cleanup());
  });

  return (
    <Noise
      class={cn(
        "flex flex-col grow relative",
        !windowCtx.maximized() && [
          themeCtx.theme().windowRounding,
          "electron-corner-smoothing-[60%] border",
        ],
      )}
      enabled={showNoise()}
    >
      <Panels.View.Root />

      <StatusBar.StatusBar />
    </Noise>
  );
};

export default App;
