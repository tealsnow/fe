import {
  createSignal,
  onCleanup,
  onMount,
  Show,
  Index,
  Setter,
  Component,
} from "solid-js";

import { cn } from "~/lib/cn";
import {
  NotificationProvider,
  notify,
  notifyPromise,
} from "~/lib/notifications";

import { Icon, iconKinds, icons } from "~/assets/icons";

import * as Theme from "~/ui/Theme";
import Button from "~/ui/components/Button";
import StatusBar, {
  StatusBarContextProvider,
  useStatusBarContext,
  StatusBarItem,
} from "~/ui/StatusBar";
import { useWindowContext, WindowContextProvider } from "~/ui/Window";

import { Test as PanelsTest } from "~/ui/Panels/test";

export const App: Component = () => {
  return (
    <WindowContextProvider>
      <AfterWindow />
    </WindowContextProvider>
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
  Theme.applyTheme(Theme.defaultTheme);

  const windowCtx = useWindowContext();

  return (
    <Theme.ThemeContextProvider
      theme={Theme.defaultTheme}
      class="flex w-screen h-screen"
      applyRounding={!windowCtx.maximized()}
    >
      <NotificationProvider>
        <StatusBarContextProvider>
          <Root />
        </StatusBarContextProvider>
      </NotificationProvider>
    </Theme.ThemeContextProvider>
  );
};

const Root: Component = () => {
  const [showNoise, _setShowNoise] = createSignal(true);

  const windowCtx = useWindowContext();
  const themeCtx = Theme.useThemeContext();

  // onMount(() => {
  //   // setupDebugPanels();
  //   // return;

  //   const { tree, setTree } = usePanelContext();

  //   Effect.gen(function* () {
  //     const root = tree.root;

  //     const tabs = yield* Panel.Node.Parent.create(
  //       setTree,
  //       {
  //         layout: Panel.Layout.Tabs(),
  //       },
  //       { addTo: root },
  //     );

  //     yield* Panel.Node.Leaf.create(
  //       setTree,
  //       {
  //         title: "dbg",
  //         content: Option.some(async () => ({
  //           default: () => <Dbg setShowNoise={setShowNoise} />,
  //         })),
  //       },
  //       { addTo: tabs },
  //     );
  //     yield* Panel.Node.Leaf.create(
  //       setTree,
  //       {
  //         title: "theme showcase",
  //         content: Option.some(async () => ({
  //           default: () => <ThemeShowcase />,
  //         })),
  //       },
  //       { addTo: tabs },
  //     );
  //   }).pipe(effectEdgeRunSync);
  // });

  const statusBarCtx = useStatusBarContext();

  onMount(() => {
    const [cleanup] = statusBarCtx.addItem({
      item: StatusBarItem.iconButton({
        icon: () => "bell",
        onClick: () => {
          console.log("clicked!");
        },
      }),
      alignment: "right",
    });
    onCleanup(() => cleanup());
  });

  return (
    <div
      class={cn(
        "flex flex-col grow relative",
        !windowCtx.maximized() && [
          themeCtx.theme().windowRounding,
          "electron-corner-smoothing-[60%] border border-theme-border",
        ],
      )}
    >
      <Show when={showNoise()}>
        <BackgroundNoise class={themeCtx.theme().windowRounding} />
      </Show>

      <PanelsTest />

      <StatusBar />
    </div>
  );
};

const BackgroundNoise: Component<{
  class?: string;
}> = (props) => {
  return (
    <svg
      class={cn(
        "w-full h-full absolute inset-0 pointer-events-none overflow-none",
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

const _Dbg: Component<{
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
    return (
      <div class="flex flex-col m-2">
        <h3 class="text-lg underline">Notifications</h3>

        <div class="flex flex-row flex-wrap gap-2">
          <Button onClick={() => notify("def")}>default</Button>

          <Button
            onClick={() => {
              setTimeout(() => {
                notify("one sec later");
              }, 1000);
            }}
          >
            in one second
          </Button>

          <Button onClick={() => notify("success", { type: "success" })}>
            success
          </Button>

          <Button onClick={() => notify("error", { type: "error" })}>
            error
          </Button>

          <Button onClick={() => notify("warning", { type: "warning" })}>
            warning
          </Button>

          <Button onClick={() => notify("info", { type: "info" })}>info</Button>

          <Button
            onClick={() => {
              notify(
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
                { duration: false },
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
              notifyPromise(succeedOrFail, {
                pending: "Processing your request...",
                success: "Request completed successfully!",
                error: "Request failed. Please try again.",
              }).catch(() => {});
            }}
          >
            promise
          </Button>
        </div>
      </div>
    );
  };

  const StatusBarTest: Component = () => {
    const statusBarCtx = useStatusBarContext();

    const [startText, setStartText] = createSignal("foo bar");

    onMount(() => {
      const [cleanup1, _id1] = statusBarCtx.addItem({
        item: StatusBarItem.text({ value: startText }),
        alignment: "left",
      });

      const [cleanup2, id2] = statusBarCtx.addItem({
        item: StatusBarItem.text({ value: () => "asdf" }),
        alignment: "right",
      });

      const [cleanup3, _id3] = statusBarCtx.addItem({
        item: StatusBarItem.textButton({
          value: () => "button",
          onClick: () => {
            console.log("clicked!");
          },
        }),
        alignment: "left",
      });

      const [cleanup4, _id4] = statusBarCtx.addItem({
        item: StatusBarItem.textButton({
          value: () => "other button",
          onClick: () => {
            console.log("clicked!");
          },
        }),
        alignment: "right",
        after: id2,
      });

      const [cleanup5, _id5] = statusBarCtx.addItem({
        item: StatusBarItem.iconButton({
          icon: () => "bell",
          onClick: () => {
            console.log("bell!");
          },
        }),
        alignment: "right",
      });

      const [cleanup6, _id6] = statusBarCtx.addItem({
        item: StatusBarItem.divider(),
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

const _ThemeShowcase: Component = () => {
  const Colors: Component = () => {
    return (
      <div class="flex flex-row justify-evenly text-center">
        <Index each={Theme.colors}>
          {(color) => {
            return (
              <div
                class="m-1 flex size-16 flex-grow flex-row content-center
                  items-center justify-center gap-2 border-2 shadow-md"
                style={{
                  background: `var(--theme-colors-${color()}-background)`,
                  "border-color": `var(--theme-colors-${color()}-border)`,
                }}
              >
                <div
                  class="size-5 border-2"
                  style={{
                    background: `var(--theme-colors-${color()}-base)`,
                    "border-color": `var(--theme-colors-${color()}-border)`,
                  }}
                />
                {color()}
              </div>
            );
          }}
        </Index>
      </div>
    );
  };

  const Icons: Component = () => {
    return (
      <div class="flex flex-row flex-wrap justify-evenly text-center">
        <Index each={iconKinds}>
          {(kind) => {
            return (
              <div
                class="m-1 flex-grow flex-col content-center items-center
                  justify-center rounded-sm p-2 text-xs shadow-md"
              >
                {kind()}
                <Icon
                  icon={icons[kind()]}
                  noDefaultStyles={kind() === "fe"}
                  class="size-10"
                />
              </div>
            );
          }}
        </Index>
      </div>
    );
  };

  return (
    <div class="flex-col overflow-auto w-full">
      <Colors />
      <Icons />
      <Index each={Theme.themeDescFlat}>
        {(item) => {
          return (
            <div
              class="m-1 flex flex-row items-center gap-2 border border-black
                p-1"
            >
              <div
                class="size-6 border border-black"
                style={{
                  background: `var(--theme-${item().join("-")})`,
                }}
              />
              <p class="font-mono">{item().join("-")}</p>
            </div>
          );
        }}
      </Index>
    </div>
  );
};

export default App;
