import { Component, createContext } from "solid-js";
import { ToastPromiseMessages } from "solid-notifications";
import { Data } from "effect";

import UUID from "~/lib/UUID";

export type Handle = {
  id: UUID;
  dismiss: (reason: string) => void;
};
export const Handle = Data.case<Handle>();

export type Content = Component<{ notif: Handle }> | string;

export type Level =
  | "default"
  | "success"
  | "error"
  | "loading"
  | "warning"
  | "info";

export interface Options {
  level?: Level;
  durationMs?: number | false;
}

export type Config = {
  durationMs: number;
};

export type PromiseMessages = ToastPromiseMessages;

export type Entry = {
  notif: Handle;
  level: Level;
  content: string;
};
export const Entry = Data.case<Entry>();

export type Context = {
  config: Config;

  notifications: Entry[];

  notify: (content: Content, opts?: Options) => Handle;
  notifyPromise: <T>(
    promise: Promise<T>,
    messages: PromiseMessages,
    opts?: Options,
  ) => Promise<T>;
};

export const Context = createContext<Context>();
