import {
  createSignal,
  onCleanup,
  onMount,
  useContext as solidUseContext,
  ParentComponent,
} from "solid-js";

import { Context } from "./Context";

export const Provider: ParentComponent<{}> = (props) => {
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
    <Context.Provider
      value={{
        maximized,
        minimize: () => window.electron.ipcRenderer.send("window/minimize"),
        toggleMaximize: () =>
          window.electron.ipcRenderer.send("window/toggleMaximize"),
        close: () => window.electron.ipcRenderer.send("window/close"),
      }}
    >
      {props.children}
    </Context.Provider>
  );
};

export const useContext = (): Context => {
  const ctx = solidUseContext(Context);
  if (!ctx)
    throw new Error(
      "Cannot use Window Context outside of a Window Context Provider",
    );
  return ctx;
};
