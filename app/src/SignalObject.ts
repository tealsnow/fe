import { Accessor, Setter, Signal } from "solid-js";
import { SetStoreFunction, Store } from "solid-js/store";

export type SignalObject<T> = { get: Accessor<T>; set: Setter<T> };

export const signalObjectFromSignal = <T>(
  signal: Signal<T>,
): SignalObject<T> => {
  const [get, set] = signal;
  return { get, set };
};

export type StoreObject<T> = { val: Store<T>; set: SetStoreFunction<T> };

export const storeObjectFromStore = <T>(
  store: [val: Store<T>, set: SetStoreFunction<T>],
): StoreObject<T> => {
  const [val, set] = store;
  return { val, set };
};
