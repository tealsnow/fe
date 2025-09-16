import {
  createSignal,
  onCleanup,
  onMount,
  Show,
  For,
  Accessor,
  createContext,
  useContext,
  ParentProps,
  Index,
  Setter,
  Component,
} from "solid-js";

import { Effect, Option } from "effect";

import effectEdgeRunSync from "~/lib/effectEdgeRunSync";
import { cn } from "~/lib/cn";

import {
  NotificationProvider,
  notify,
  notifyPromise,
} from "~/lib/notifications";
import * as theming from "~/Theme";
import ThemeProvider from "~/ThemeProvider";

import { Icon, IconKind, iconKinds } from "~/assets/icons";

import Button from "~/ui/components/Button";

import PanelsRoot, { setupDebugPanels } from "~/panels/panels";
import { PanelContextProvider, usePanelContext } from "./panels/PanelContext";
import * as Panel from "~/panels/Panel";

export const App: Component = () => {
  // @NOTE: This applies the theme globally - setting the css vars on the
  //  document globally. This is mostly just for the toasts, since they
  //  are built with normal css.
  //  If that changes to use inline styles and/or tailwind we can remove this
  //
  //  As is stands this works just fine, if and when we do a theme preview
  //  we can just use the provider, unless we want to show what toast would
  //  look like...
  theming.applyTheme(theming.defaultTheme);

  return (
    <WindowContextProvider>
      <ThemeProvider theme={theming.defaultTheme} class="w-screen h-screen">
        <NotificationProvider>
          <PanelContextProvider initialTitlebar={Titlebar}>
            <Root />
          </PanelContextProvider>
        </NotificationProvider>
      </ThemeProvider>
    </WindowContextProvider>
  );
};

const Root: Component = () => {
  const [showNoise, setShowNoise] = createSignal(true);

  const windowCtx = useWindowContext();

  onMount(() => {
    // setupDebugPanels();
    // return;

    const { tree, setTree } = usePanelContext();

    Effect.gen(function* () {
      const root = tree.root;

      const tabs = yield* Panel.Node.Parent.create(
        setTree,
        {
          layout: Panel.Layout.Tabs(),
        },
        { addTo: root },
      );

      yield* Panel.Node.Leaf.create(
        setTree,
        {
          title: "dbg",
          content: Option.some(async () => ({
            default: () => <Dbg setShowNoise={setShowNoise} />,
          })),
        },
        { addTo: tabs },
      );
      yield* Panel.Node.Leaf.create(
        setTree,
        {
          title: "theme showcase",
          content: Option.some(async () => ({
            default: () => <ThemeShowcase />,
          })),
        },
        { addTo: tabs },
      );
    }).pipe(effectEdgeRunSync);
  });

  return (
    <div
      class={cn(
        "flex flex-col w-full h-full",
        !windowCtx.maximized() && "border border-theme-border",
      )}
    >
      <Show when={showNoise()}>
        <BackgroundNoise />
      </Show>

      <PanelsRoot />

      {/*<StatusBar />*/}
    </div>
  );
};

const Titlebar: Component = () => {
  type WindowButton = {
    icon: () => IconKind;
    onClick: () => void;
  };

  const windowCtx = useWindowContext();

  const windowButtons = (): WindowButton[] => [
    {
      icon: () => "window_minimize",
      onClick: windowCtx.minimize,
    },
    {
      icon: () =>
        windowCtx.maximized() ? "window_restore" : "window_maximize",
      onClick: windowCtx.toggleMaximize,
    },
    {
      icon: () => "close",
      onClick: windowCtx.close,
    },
  ];

  return (
    <>
      <div class="flex flex-row h-full w-full items-center window-drag">
        <Icon kind="fe" class="size-4 mx-1" />

        <div class="grow h-full block" />

        <div class="flex h-full -window-drag">
          <For each={windowButtons()}>
            {(button) => (
              <div
                class="hover:bg-theme-icon-base-fill
                active:bg-theme-icon-active-fill inline-flex h-full w-8
                items-center justify-center hover:cursor-pointer"
                onClick={button.onClick}
              >
                <Icon kind={button.icon()} class="size-4" />
              </div>
            )}
          </For>
        </div>
      </div>
    </>
  );
};

const BackgroundNoise: Component = () => {
  return (
    <svg
      class="w-full h-full absolute inset-0 pointer-events-none"
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

export type WindowContext = {
  maximized: Accessor<boolean>;
  minimize: () => void;
  toggleMaximize: () => void;
  close: () => void;
};
export const WindowContext = createContext<WindowContext>();
export const useWindowContext = (): WindowContext => {
  const ctx = useContext(WindowContext);
  if (!ctx)
    throw new Error(
      "Cannot use useWindowContext outside of a WindowContextProvider",
    );
  return ctx;
};
export type WindowContextProviderProps = ParentProps<{}>;
export const WindowContextProvider: Component<WindowContextProviderProps> = (
  props,
) => {
  const [maximized, setMaximized] = createSignal(
    window.electron.ipcRenderer.sendSync("get window/isMaximized"),
  );

  onMount(() => {
    const cleanups: (() => void)[] = [];
    cleanups.push(
      window.electron.ipcRenderer.on("on window/maximized", () =>
        setMaximized(true),
      ),
    );
    cleanups.push(
      window.electron.ipcRenderer.on("on window/unmaximized", () =>
        setMaximized(false),
      ),
    );
    onCleanup(() => cleanups.map((fn) => fn()));
  });

  return (
    <WindowContext.Provider
      value={{
        maximized,
        minimize: () => window.electron.ipcRenderer.send("window/minimize"),
        toggleMaximize: () =>
          window.electron.ipcRenderer.send("window/toggleMaximize"),
        close: () => window.electron.ipcRenderer.send("window/close"),
      }}
    >
      {props.children}
    </WindowContext.Provider>
  );
};

type DbgProps = { setShowNoise: Setter<boolean> };
const Dbg: Component<DbgProps> = (props) => {
  const plus100 = window.api.native.plus100(5);
  const greet = window.api.native.greet("world");
  const numCpus = window.api.native.getNumCpus();

  return (
    <div class="flex flex-col w-full gap-2">
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

      <hr />

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
      </div>

      <hr />

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
                  const _ = Math.random() > 0.5 ? resolve() : reject();
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
    </div>
  );
};

const ThemeShowcase: Component = () => {
  const Colors: Component = () => {
    return (
      <div class="flex flex-row justify-evenly text-center">
        <Index each={theming.colors}>
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
                <Icon kind={kind()} class="size-10" />
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
      <Index each={theming.themeDescFlat}>
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
