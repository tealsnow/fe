import { Context, createContext } from "solid-js";

export function createHotStableContext<T>(
  name: string,
  defaultValue?: T,
): Context<T> {
  const contextKey = `hot-context-${name}`;

  const { hot } = import.meta;
  if (hot) {
    return (hot.data[contextKey] ??= createContext<T>(defaultValue as T));
  } else {
    return createContext<T>(defaultValue as T);
  }
}
export default createHotStableContext;
