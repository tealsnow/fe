import { createRoot, For, Match, onMount, Switch } from "solid-js";
import { createStore } from "solid-js/store";
import { Icon, iconKinds } from "./assets/icons";
import { NotificationProvider, notify, notifyPromise } from "./notifications";
import StatusBar, { statusBar } from "./StatusBar";
import * as theming from "./theme";
import Titlebar from "./Titlebar";
import { mkTestWorkspace, mkWorkspace, WorkspaceState } from "./Workspace";

import DND from "./dnd_tut";
import Panels from "./panels";

const App = () => {
  theming.applyTheme(theming.defaultTheme);

  return (
    <div class="flex h-screen w-screen flex-col overflow-hidden">
      <NotificationProvider>
        <Root />
      </NotificationProvider>
    </div>
  );
};

const Root = () => {
  onMount(() => {
    const item = statusBar.createItem({
      id: "fe.notifications",
      alignment: "right",
      kind: "button",
    });
    item.content = () => <Icon kind="bell" class="size-4" />;
    item.onClick = () => {
      notify("yo ho ho");
    };
  });

  const [workspaceState, setWorkspaceState] = createStore<WorkspaceState>({
    workspaces: [
      mkWorkspace({
        title: "Theme Showcase",
        render: () => ThemeShowcase,
      }),
      mkWorkspace({
        title: "panels",
        render: () => Panels,
      }),
      mkWorkspace({
        title: "Dnd2",
        render: () => DND,
      }),
      mkWorkspace({
        title: "Notifications",
        render: () => Notifications,
      }),
      mkWorkspace({
        title: "Icons",
        render: () => Icons,
      }),
      mkWorkspace({
        title: "Stores",
        render: () => Stores,
      }),
    ],
    activeIndex: 0,
  });

  return (
    <>
      <Titlebar
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

      <div class="box-border grow overflow-y-auto">
        <Switch fallback={<div>{/* @TODO */}</div>}>
          <For each={workspaceState.workspaces}>
            {(workspace, index) => {
              return (
                <Match when={workspaceState.activeIndex === index()}>
                  <div data-index={index()}>
                    {/* @ts-ignore: not sure what is complaining about, but all is working */}
                    {workspace.render()}
                  </div>
                </Match>
              );
            }}
          </For>
        </Switch>
      </div>

      <StatusBar />
    </>
  );
};

const Notifications = () => {
  return (
    <div class="m-2 flex flex-row flex-wrap gap-2">
      <button class="btn-primary" onClick={() => notify("def")}>
        default
      </button>

      <button
        class="btn-primary"
        onClick={() => {
          setTimeout(() => {
            notify("one sec later");
          }, 1000);
        }}
      >
        in one second
      </button>

      <button
        class="btn-primary"
        onClick={() => notify("success", { type: "success" })}
      >
        success
      </button>

      <button
        class="btn-primary"
        onClick={() => notify("error", { type: "error" })}
      >
        error
      </button>

      <button
        class="btn-primary"
        onClick={() => notify("warning", { type: "warning" })}
      >
        warning
      </button>

      <button
        class="btn-primary"
        onClick={() => notify("info", { type: "info" })}
      >
        info
      </button>

      <button
        class="btn-primary"
        onClick={() => {
          notify(
            ({ notif }) => {
              return (
                <div class="flex-col gap-3 px-2">
                  <p>Are you sure?</p>

                  <div class="flex-row gap-2">
                    <button
                      class="btn-primary"
                      onClick={() => notif.dismiss("yes")}
                    >
                      Yes
                    </button>

                    <button
                      class="btn-secondary"
                      onClick={() => notif.dismiss("no")}
                    >
                      No
                    </button>
                  </div>
                </div>
              );
            },
            { duration: false },
          );
        }}
      >
        confirm
      </button>

      <button
        class="btn-primary"
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
      </button>
    </div>
  );
};

const personStore = createRoot(() =>
  createStore({
    name: {
      first: "brandon",
      last: "sanderson",
    },
    age: 45,
    books: [
      { title: "The Final Empire", series: "Mistborn", kind: "Novel" },
      { title: "Oathbringer", series: "Stormlight", kind: "Novel" },
      { title: "Secret History", series: "Mistborn", kind: "Novela" },
    ],
  }),
);

const Stores = () => {
  const [person, setPerson] = personStore;

  const addMistbornPrefixes = () => {
    setPerson(
      "books",
      (b) => b.series == "Mistborn",
      "title",
      (old) => `Mistborn: ${old}`,
    );
  };

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

      <button class="btn-primary" onClick={addMistbornPrefixes}>
        update books
      </button>

      <button
        class="btn-primary"
        onClick={() => {
          setPerson("name", "last", "bar");
        }}
      >
        change last name
      </button>
    </div>
  );
};

const Icons = () => {
  return (
    <div class="flex flex-row flex-wrap justify-evenly text-center">
      <For each={iconKinds}>
        {(kind) => {
          return (
            <div class="m-1 flex-grow flex-col content-center items-center justify-center rounded-sm p-2 text-xs shadow-md">
              {kind}
              <Icon
                kind={kind}
                noDefaultStyles={kind === "fe"}
                class="size-10"
              />
            </div>
          );
        }}
      </For>
    </div>
  );
};

const Colors = () => {
  return (
    <div class="flex flex-row justify-evenly text-center">
      <For
        each={[
          "red",
          "orange",
          "yellow",
          "green",
          "aqua",
          "blue",
          "purple",
          "pink",
        ]}
      >
        {(color, index) => {
          return (
            <div
              data-index={index()}
              class="m-1 flex size-16 flex-grow flex-row content-center items-center justify-center gap-2 border-2 shadow-md"
              style={{
                background: `var(--theme-colors-${color}-background)`,
                "border-color": `var(--theme-colors-${color}-border)`,
              }}
            >
              <div
                class="size-5 border-2"
                style={{
                  background: `var(--theme-colors-${color}-base)`,
                  "border-color": `var(--theme-colors-${color}-border)`,
                }}
              ></div>
              {color}
            </div>
          );
        }}
      </For>
    </div>
  );
};

const ThemeShowcase = () => {
  const flat = theming.themeDescFlat;

  return (
    <div class="flex-col">
      <Colors />
      <For each={flat}>
        {(item) => {
          return (
            <div class="m-1 flex flex-row items-center gap-2 border border-black p-1">
              <div
                class="size-6 border border-black"
                style={{
                  background: `var(--theme-${item.join("-")})`,
                }}
              ></div>
              <p class="font-mono">{item.join("-")}</p>
            </div>
          );
        }}
      </For>
    </div>
  );
};

export default App;
