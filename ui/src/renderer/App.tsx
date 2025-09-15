import {
  createEffect,
  createRoot,
  createSignal,
  For,
  Index,
  Match,
  onMount,
  Show,
  Switch,
} from "solid-js";
import { createStore } from "solid-js/store";

import { Icon, IconKind, iconKinds } from "~/assets/icons";

import { NotificationProvider, notify, notifyPromise } from "~/notifications";
import StatusBar, { statusBar } from "~/StatusBar";
import * as theming from "~/Theme";
import ThemeProvider from "~/ThemeProvider";
import Titlebar from "~/Titlebar";
import { mkTestWorkspace, mkWorkspace, WorkspaceState } from "~/Workspace";

import { cn } from "~/lib/cn";

import Button from "~/ui/components/Button";

import DND from "~/dnd_tut";
import { PanelsRoot } from "~/panels/panels";

const App = () => {
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

  onMount(() => {
    const bell = statusBar.createItem({
      id: "fe.notifications",
      alignment: "right",
      kind: "button",
    });
    bell.content = () => <Icon kind="bell" class="size-4" />;
    bell.onClick = () => {
      notify("yo ho ho");
    };

    const showNoiseBtn = statusBar.createItem({
      id: "fe.showNoise",
      alignment: "left",
      kind: "button",
    });
    createEffect(() => {
      // eslint-disable-next-line solid/reactivity
      showNoiseBtn.content = () => {
        const kind: IconKind = showNoise()
          ? "window_restore"
          : "window_maximize";
        return <Icon kind={kind} class="size-4" />;
      };
      showNoiseBtn.onClick = () => {
        setShowNoise((b) => !b);
      };
    });
  });

  const [workspaceState, setWorkspaceState] = createStore<WorkspaceState>({
    workspaces: [
      // mkWorkspace({
      //   title: "Panels",
      //   render: Panels,
      // }),
      mkWorkspace({
        title: "Native Test",
        render: NativeTest,
      }),
      mkWorkspace({
        title: "Theme Showcase",
        render: ThemeShowcase,
      }),
      mkWorkspace({
        title: "Dnd2",
        render: DND,
      }),
      mkWorkspace({
        title: "Notifications",
        render: Notifications,
      }),
      mkWorkspace({
        title: "Icons",
        render: Icons,
      }),
      mkWorkspace({
        title: "Stores",
        render: Stores,
      }),
    ],
    activeIndex: 0,
  });

  const [windowMaximized, setWindowMaximized] = createSignal(
    window.electron.ipcRenderer.sendSync("get window/isMaximized"),
  );

  onMount(() => {
    window.electron.ipcRenderer.on("on window/maximized", () => {
      setWindowMaximized(true);
    });
    window.electron.ipcRenderer.on("on window/unmaximized", () => {
      setWindowMaximized(false);
    });
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

      <Titlebar
        windowMaximized={windowMaximized}
        workspaces={workspaceState.workspaces}
        activeIndex={workspaceState.activeIndex}
        onReorder={(oldIdx, newIdx) => {
          setWorkspaceState("workspaces", (prev) => {
            const items = [...prev];
            const [moved] = items.splice(oldIdx, 1);
            items.splice(newIdx, 0, moved);
            return items;
          });
          setWorkspaceState("activeIndex", newIdx);
        }}
        onActiveIndexChange={(index) => setWorkspaceState("activeIndex", index)}
        onCloseClick={(index) => {
          if (index === workspaceState.activeIndex) {
            if (workspaceState.workspaces.length === 0) {
              setWorkspaceState("activeIndex", undefined);
            } else if (workspaceState.activeIndex === 0) {
              setWorkspaceState("activeIndex", 0);
            } else {
              setWorkspaceState("activeIndex", (prev) => prev! - 1);
            }
          }

          setWorkspaceState("workspaces", (prev) => {
            const newTabs = [...prev];
            newTabs.splice(index, 1); // discard
            return newTabs;
          });
        }}
        onNewClick={() => {
          const newIdx = workspaceState.workspaces.length;
          setWorkspaceState("workspaces", (prev) => [
            ...prev,
            mkTestWorkspace("new tab"),
          ]);
          setWorkspaceState("activeIndex", newIdx);
        }}
      />

      <div class="flex flex-col grow overflow-hidden">
        <Switch fallback={<div>{/* @TODO */}</div>}>
          <For each={workspaceState.workspaces}>
            {(workspace, index) => {
              return (
                <Match when={workspaceState.activeIndex === index()}>
                  {workspace.render({})}
                </Match>
              );
            }}
          </For>
        </Switch>
      </div>

      <StatusBar />
    </div>
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

const Notifications = () => {
  return (
    <div class="m-2 flex flex-row flex-wrap gap-2">
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

      <Button onClick={() => notify("error", { type: "error" })}>error</Button>

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
  );
};

const personStore = createRoot(
  () =>
    // cspell:disable
    // eslint-disable-next-line solid/reactivity
    createStore({
      name: {
        first: "Brandon",
        last: "Sanderson",
      },
      age: 45,
      books: [
        { title: "The Final Empire", series: "Mistborn", kind: "Novel" },
        { title: "Oathbringer", series: "Stormlight", kind: "Novel" },
        { title: "Secret History", series: "Mistborn", kind: "Novela" },
      ],
    }),
  // cspell:enable
);

const Stores = () => {
  const [person, setPerson] = personStore;

  // cspell:disable
  const addPrefixes = () => {
    setPerson(
      "books",
      (b) => b.series == "Mistborn",
      "title",
      (old) => `Mistborn: ${old}`,
    );
  };
  // cspell:enable

  return (
    <div class="flex flex-col gap-3">
      <div>
        <p>first name: {person.name.first}</p>
        <p>last name: {person.name.last}</p>
      </div>

      <For each={person.books}>
        {(book) => (
          <div>
            <h2 class="text-xl">{book.title}</h2>
            <h3 class="text-lg">{book.series}</h3>
            <h4>{book.kind}</h4>
          </div>
        )}
      </For>

      <Button onClick={addPrefixes}>update books</Button>

      <Button
        onClick={() => {
          setPerson("name", "last", "bar");
        }}
      >
        change last name
      </Button>
    </div>
  );
};

const Icons = () => {
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

const Colors = () => {
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

const ThemeShowcase = () => {
  return (
    <div class="flex-col overflow-auto w-full">
      <Colors />
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

const NativeTest = () => {
  const plus100 = window.api.native.plus100(5);
  const greet = window.api.native.greet("world");
  const numCpus = window.api.native.getNumCpus();

  return (
    <div class="w-full h-full flex flex-col gap-2 p-2">
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
      <Button onClick={() => window.electron.ipcRenderer.send("restart")}>
        ipc restart
      </Button>
    </div>
  );
};

export default App;
