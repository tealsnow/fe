import {
  createSignal,
  onCleanup,
  onMount,
  Show,
  Setter,
  Component,
  For,
} from "solid-js";

import { Effect, Option } from "effect";

import { Icon, icons } from "~/assets/icons";

import { cn } from "~/lib/cn";
import Integer from "~/lib/Integer";
import * as Notif from "~/lib/Notif";

import * as Theme from "~/ui/Theme";
import Button from "~/ui/components/Button";
import * as StatusBar from "~/ui/StatusBar";
import * as Window from "~/ui/Window";
import * as Panels from "~/ui/Panels";

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
              <div class="border-theme-border border p-2 rounded-md">
                {entry.content}
              </div>
            )}
          </For>
        </div>
      ),
    });

    const [cleanup, _id] = statusBarCtx.addItem({
      alignment: "right",
      item: StatusBar.BarItem.iconButton({
        icon: () => <Icon icon={icons["bell"]} />,
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
    <div
      class={cn(
        "bg-theme-background flex flex-col grow relative",
        !windowCtx.maximized() && [
          themeCtx.theme().windowRounding,
          "electron-corner-smoothing-[60%] border border-theme-border",
        ],
      )}
    >
      <Show when={showNoise()}>
        <BackgroundNoise class={themeCtx.theme().windowRounding} />
      </Show>

      <Panels.View.Root />

      <StatusBar.StatusBar />
    </div>
  );
};

const BackgroundNoise: Component<{
  class?: string;
}> = (props) => {
  return (
    <svg
      class={cn(
        "w-full h-full absolute inset-0 pointer-events-none",
        props.class,
      )}
      style={{ opacity: 0.3, "mix-blend-mode": "soft-light" }}
    >
      <filter id="noiseFilter" x={0} y={0} width="100%" height="100%">
        <feTurbulence
          type="fractalNoise"
          // type="turbulence"
          baseFrequency="0.32"
          numOctaves={2}
          stitchTiles="stitch"
          result="turbulence"
        />
        <feComponentTransfer in="turbulence" result="darken">
          <feFuncR type="linear" slope="0.8" intercept="0" />
          <feFuncG type="linear" slope="0.8" intercept="0" />
          <feFuncB type="linear" slope="0.8" intercept="0" />
        </feComponentTransfer>
        <feDisplacementMap
          in="sourceGraphic"
          in2="darken"
          scale={25}
          xChannelSelector="R"
          yChannelSelector="G"
          result="displacement"
        />
        <feBlend
          mode="multiply"
          in="sourceGraphic"
          in2="displacement"
          result="multiply"
        />
        <feColorMatrix in="multiply" type="saturate" values="0" />
      </filter>

      <rect
        width="100%"
        height="100%"
        filter="url(#noiseFilter)"
        fill="transparent"
      />
    </svg>
  );
};

const Dbg: Component<{
  setShowNoise: Setter<boolean>;
}> = (props) => {
  const Settings: Component = () => {
    return (
      <div class="flex flex-col m-2">
        <h3 class="text-lg underline">Settings</h3>

        <Button
          class="w-fit"
          onClick={() => {
            props.setShowNoise((old) => !old);
          }}
        >
          toggle background noise
        </Button>
      </div>
    );
  };

  const NativeTest: Component = () => {
    const plus100 = window.api.native.plus100(5);
    const greet = window.api.native.greet("world");
    const numCpus = window.api.native.getNumCpus();

    return (
      <div class="flex flex-col gap-2 w-fit m-2">
        <h3 class="text-lg underline">Native Test</h3>

        <p>plus100: '{plus100}'</p>
        <p>greet: '{greet}'</p>
        <p>numCpus: '{numCpus}'</p>
        <Button
          onClick={() =>
            window.api.native.printArray(new Uint8Array([1, 2, 3, 4, 5]))
          }
        >
          Print array
        </Button>
        <Button onClick={() => window.electron.ipcRenderer.send("ping")}>
          ipc test (ping)
        </Button>
        <Button onClick={() => window.electron.ipcRenderer.send("reload")}>
          ipc reload
        </Button>
        {/*<Button onClick={() => window.electron.ipcRenderer.send("restart")}>
          ipc restart
        </Button>*/}
        <Button onClick={() => window.api.native.printCwd()}>print cwd</Button>
        <Button onClick={() => window.api.native.printArch()}>
          print arch
        </Button>
      </div>
    );
  };

  const NotificationsTest: Component = () => {
    const ctx = Notif.useContext();
    return (
      <div class="flex flex-col m-2">
        <h3 class="text-lg underline">Notifications</h3>

        <div class="flex flex-row flex-wrap gap-2">
          <Button onClick={() => ctx.notify("def")}>default</Button>

          <Button
            onClick={() => {
              setTimeout(() => {
                ctx.notify("one sec later");
              }, 1000);
            }}
          >
            in one second
          </Button>

          <Button onClick={() => ctx.notify("success", { level: "success" })}>
            success
          </Button>

          <Button onClick={() => ctx.notify("error", { level: "error" })}>
            error
          </Button>

          <Button onClick={() => ctx.notify("warning", { level: "warning" })}>
            warning
          </Button>

          <Button onClick={() => ctx.notify("info", { level: "info" })}>
            info
          </Button>

          <Button
            onClick={() => {
              ctx.notify(
                (props) => {
                  return (
                    <div class="flex flex-col gap-3 px-2">
                      <p>Are you sure?</p>

                      <div class="flex flex-row gap-2">
                        <Button
                          color="green"
                          size="small"
                          onClick={() => props.notif.dismiss("yes")}
                        >
                          Yes
                        </Button>

                        <Button
                          color="red"
                          size="small"
                          onClick={() => props.notif.dismiss("no")}
                        >
                          No
                        </Button>
                      </div>
                    </div>
                  );
                },
                { durationMs: false },
              );
            }}
          >
            confirm
          </Button>

          <Button
            onClick={() => {
              const succeedOrFail = new Promise<void>((resolve, reject) => {
                setTimeout(() => {
                  Math.random() > 0.5 ? resolve() : reject();
                }, 2000);
              });
              ctx
                .notifyPromise(succeedOrFail, {
                  pending: "Processing your request...",
                  success: "Request completed successfully!",
                  error: "Request failed. Please try again.",
                })
                .catch(() => {});
            }}
          >
            promise
          </Button>
        </div>
      </div>
    );
  };

  const StatusBarTest: Component = () => {
    const statusBarCtx = StatusBar.useContext();

    const [startText, setStartText] = createSignal("foo bar");

    onMount(() => {
      const [cleanup1, _id1] = statusBarCtx.addItem({
        item: StatusBar.BarItem.text({
          value: startText,
          tooltip: () => "a",
        }),
        alignment: "left",
      });

      const [cleanup2, id2] = statusBarCtx.addItem({
        item: StatusBar.BarItem.text({
          value: () => "asdf",
          tooltip: () => "b",
        }),
        alignment: "right",
      });

      const [cleanup3, _id3] = statusBarCtx.addItem({
        item: StatusBar.BarItem.textButton({
          value: () => "button",
          tooltip: () => "c",
          onClick: () => {
            console.log("clicked!");
          },
        }),
        alignment: "left",
      });

      const [cleanup4, _id4] = statusBarCtx.addItem({
        item: StatusBar.BarItem.textButton({
          value: () => "other button",
          tooltip: () => "d",
          onClick: () => {
            console.log("clicked!");
          },
        }),
        alignment: "right",
        after: id2,
      });

      const [cleanup5, _id5] = statusBarCtx.addItem({
        item: StatusBar.BarItem.iconButton({
          icon: () => "bell",
          tooltip: () => "e",
          onClick: () => {
            console.log("bell!");
          },
        }),
        alignment: "right",
      });

      const [cleanup6, _id6] = statusBarCtx.addItem({
        item: StatusBar.BarItem.divider(),
        alignment: "left",
      });

      onCleanup(() => {
        cleanup1();
        cleanup2();
        cleanup3();
        cleanup4();
        cleanup5();
        cleanup6();
      });
    });

    return (
      <div class="flex flex-col gap-2 p-2">
        <h3 class="text-lg underline">Status Bar</h3>

        <Button
          color="green"
          onClick={() => {
            setStartText("updated!");
          }}
        >
          Update text
        </Button>
      </div>
    );
  };

  const _ignore = StatusBarTest;

  return (
    <div class="flex flex-col w-full gap-2">
      <Settings />
      <hr />
      <NativeTest />
      <hr />
      <NotificationsTest />
      {/*<hr />
      <StatusBarTest />*/}
    </div>
  );
};

export default App;
