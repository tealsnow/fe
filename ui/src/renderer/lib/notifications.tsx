import { Component, ParentProps } from "solid-js";
import {
  Toaster,
  ToastProvider,
  showToast,
  dismissToast,
  ToastOptions,
  ToastPromiseMessages,
  promiseToast,
} from "solid-notifications";
import { v4 as uuidv4 } from "uuid";

export type NotificationConfig = {
  durationMs: number;
};

export type NotificationInterface = {
  config: NotificationProviderProps;
};

export const notificationInterface: NotificationInterface = {
  config: { durationMs: 5000 },
};

export type NotificationProviderProps = ParentProps<
  Partial<NotificationConfig>
>;

export const NotificationProvider: Component<NotificationProviderProps> = (
  props,
) => {
  // eslint-disable-next-line solid/reactivity
  if (props.durationMs)
    // eslint-disable-next-line solid/reactivity
    notificationInterface.config.durationMs = props.durationMs;

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
    >
      <Toaster />
      {props.children}
    </ToastProvider>
  );
};

export interface Notification {
  id: string;
  dismiss: (reason: string) => void;
}

export type NotificationContent = Component<{ notif: Notification }> | string;

export type NotificationType =
  | "default"
  | "success"
  | "error"
  | "loading"
  | "warning"
  | "info";

export interface NotificationOptions {
  type?: NotificationType;
  duration?: number | false;
}

const toastOptionsFromNotificationOptions = (
  id?: string,
  options?: NotificationOptions,
): ToastOptions => {
  return {
    type: options?.type,
    duration: options?.duration ?? notificationInterface.config.durationMs,
    id,
    exitCallback: (reason) => {
      console.debug("toast exit reason: " + reason + " - " + !!reason);
    },
  };
};

export const notify = (
  content: NotificationContent,
  options?: NotificationOptions,
): Notification => {
  const id = uuidv4();

  const notif: Notification = {
    id,
    dismiss: (reason?: string) => {
      dismissToast({ id, reason: reason });
    },
  };

  const opts = toastOptionsFromNotificationOptions(id, options);
  if (typeof content === "string") {
    showToast(content, opts);
  } else {
    showToast(content({ notif }), opts);
  }

  return notif;
};

type NotificationPromiseMessages = ToastPromiseMessages;

export const notifyPromise = <T,>(
  promise: Promise<T>,
  messages: NotificationPromiseMessages,
  options?: NotificationOptions,
): Promise<T> => {
  return promiseToast(
    promise,
    messages,
    toastOptionsFromNotificationOptions(undefined, options),
  );
};
