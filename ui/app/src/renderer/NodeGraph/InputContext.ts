import { createContext } from "solid-js";

// prefer to use event information for modifier state
export type InputContext = {
  shift: boolean;
  ctrl: boolean;
  space: boolean;
  leftMouseButton: boolean;
};

export const InputContext = createContext<InputContext>();
