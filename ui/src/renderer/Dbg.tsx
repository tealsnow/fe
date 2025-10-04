import { createSignal, onCleanup, onMount, Setter, Component } from "solid-js";

import * as Notif from "~/lib/Notif";

import Button from "~/ui/components/Button";
import * as StatusBar from "~/ui/StatusBar";

export const Dbg: Component<{
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

export default Dbg;
