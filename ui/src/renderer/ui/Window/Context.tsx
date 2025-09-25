import { Accessor } from "solid-js";

import createHotStableContext from "~/lib/createHotStableContext";

export type WindowContext = {
  maximized: Accessor<boolean>;
  minimize: () => void;
  toggleMaximize: () => void;
  close: () => void;
};
export const WindowContext =
  createHotStableContext<WindowContext>("window-context");
