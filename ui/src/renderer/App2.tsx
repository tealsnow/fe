import { createSignal, onCleanup, onMount, Show, For } from "solid-js";

import { NotificationProvider } from "~/notifications";
import * as theming from "~/Theme";
import ThemeProvider from "~/ThemeProvider";
import { Icon, IconKind } from "~/assets/icons";
import { cn } from "~/lib/cn";

import Panels from "~/panels/panels";

export const App = () => {
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
    <ThemeProvider theme={theming.defaultTheme} class="w-screen h-screen">
      <NotificationProvider>
        <Root />
      </NotificationProvider>
    </ThemeProvider>
  );
};

const Root = () => {
  const [showNoise, setShowNoise] = createSignal(true);

  const [windowMaximized, setWindowMaximized] = createSignal(
    window.electron.ipcRenderer.sendSync("get window/isMaximized"),
  );

  onMount(() => {
    const cleanups: (() => void)[] = [];
    cleanups.push(
      window.electron.ipcRenderer.on("on window/maximized", () => {
        setWindowMaximized(true);
      }),
    );
    cleanups.push(
      window.electron.ipcRenderer.on("on window/unmaximized", () => {
        setWindowMaximized(false);
      }),
    );
    onCleanup(() => cleanups.map((fn) => fn()));
  });

  return (
    <div
      class={cn(
        "flex flex-col w-full h-full",
        !windowMaximized() && "border border-theme-border",
      )}
    >
      <Show when={showNoise()}>
        <BackgroundNoise />
      </Show>

      <Panels titlebar={() => <Titlebar windowMaximized={windowMaximized} />} />

      {/*<StatusBar />*/}
    </div>
  );
};

type TitlebarProps = {
  // @TODO: move this to a context
  windowMaximized: () => boolean;
};

const Titlebar = (props: TitlebarProps) => {
  type WindowControls = {
    minimize: () => void;
    toggleMaximize: () => void;
    close: () => void;
  };
  const WindowControls = (): WindowControls => ({
    minimize: () => {
      window.electron.ipcRenderer.send("window/minimize");
    },
    toggleMaximize: () => {
      window.electron.ipcRenderer.send("window/toggleMaximize");
    },
    close: () => {
      window.electron.ipcRenderer.send("window/close");
    },
  });

  type WindowButton = {
    icon: () => IconKind;
    onClick: () => void;
  };

  const windowControls = WindowControls();
  const windowButtons = (): WindowButton[] => [
    {
      icon: () => "window_minimize",
      onClick: windowControls.minimize,
    },
    {
      icon: () =>
        props.windowMaximized() ? "window_restore" : "window_maximize",
      onClick: windowControls.toggleMaximize,
    },
    {
      icon: () => "close",
      onClick: windowControls.close,
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

const BackgroundNoise = () => {
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

export default App;
