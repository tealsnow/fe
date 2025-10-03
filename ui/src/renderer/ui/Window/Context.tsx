import { Accessor } from "solid-js";

import createHotStableContext from "~/lib/createHotStableContext";

export type Context = {
  maximized: Accessor<boolean>;
  minimize: () => void;
  toggleMaximize: () => void;
  close: () => void;
};
export const Context = createHotStableContext<Context>("WindowContext");
