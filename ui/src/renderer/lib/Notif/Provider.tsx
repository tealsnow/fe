import {
  mergeProps,
  ParentComponent,
  useContext as solidUseContext,
} from "solid-js";
import {
  dismissToast,
  promiseToast,
  showToast,
  Toaster,
  ToastOptions,
  ToastProvider,
} from "solid-notifications";

import UUID from "~/lib/UUID";

import { Config, Context, Entry, Handle, Options } from "./Context";
import { createStore } from "solid-js/store";

const toastOptions = (
  config: Config,
  id?: string,
  options?: Options,
): ToastOptions => {
  return {
    type: options?.level,
    duration: options?.durationMs ?? config.durationMs,
    id,
    exitCallback: (reason) => {
      console.debug("toast exit reason: " + reason + " - " + !!reason);
    },
  };
};

export const Provider: ParentComponent<{
  config?: Partial<Config>;
}> = (props) => {
  // is initial
  // eslint-disable-next-line solid/reactivity
  const config = mergeProps({ durationMs: 5000 }, props.config);

  const [entries, setEntries] = createStore<Entry[]>([]);

  const notify: Context["notify"] = (content, opts) => {
    const id = UUID.make();

    const handle = Handle({
      id,
      dismiss: (reason?: string) => dismissToast({ id, reason }),
    });

    const options = toastOptions(config, id, opts);
    if (typeof content === "string") {
      setEntries((entries) => [
        ...entries,
        Entry({ notif: handle, level: options.type ?? "default", content }),
      ]);

      showToast(content, options);
    } else {
      console.warn(
        "TODO: how do we keep a record of custom rendered notifications?",
      );
      showToast(content({ notif: handle }), options);
    }

    return handle;
  };

  const notifyPromise: Context["notifyPromise"] = (promise, messages, opts) => {
    console.warn("TODO: entries for promise notifications");

    return promiseToast(
      promise,
      messages,
      toastOptions(config, undefined, opts),
    );
  };

  return (
    <ToastProvider
      positionY="bottom"
      positionX="right"
      offsetY={24 + 8}
      offsetX={8}
      //
      limit={5}
      renderOnWindowInactive={true}
      pauseOnHover={true}
      pauseOnWindowInactive={true}
      showDismissButton={true}
      dismissOnClick={false}
      showProgressBar={true}
      showIcon={true}
      dragToDismiss={false}
      //
      enterDuration={200}
      exitDuration={150}
      //
      duration={config.durationMs}
    >
      <Toaster />
      <Context.Provider
        value={{
          config,
          notifications: entries,
          notify,
          notifyPromise,
        }}
      >
        {props.children}
      </Context.Provider>
    </ToastProvider>
  );
};

export const useContext = (): Context => {
  const ctx = solidUseContext(Context);
  if (!ctx)
    throw new Error(
      "Cannot use Notif Context outside of a Notif Context Provider",
    );
  return ctx;
};
