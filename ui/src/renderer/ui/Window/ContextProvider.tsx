import {
  createSignal,
  onCleanup,
  onMount,
  useContext,
  ParentProps,
  Component,
} from "solid-js";
import { WindowContext } from "./Context";

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

export const useWindowContext = (): WindowContext => {
  const ctx = useContext(WindowContext);
  if (!ctx)
    throw new Error(
      "Cannot use useWindowContext outside of a WindowContextProvider",
    );
  return ctx;
};
