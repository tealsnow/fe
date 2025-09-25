import { Accessor, Setter, Signal } from "solid-js";
import { produce, SetStoreFunction, Store } from "solid-js/store";

/**
 * @deprecated
 */
export type SignalObject<T> = { get: Accessor<T>; set: Setter<T> };

/**
 * @deprecated
 */
export const signalObjectFromSignal = <T>(
  signal: Signal<T>,
): SignalObject<T> => {
  const [get, set] = signal;
  return { get, set };
};

/**
 * @deprecated
 */
export type StoreObject<T> = { val: Store<T>; set: SetStoreFunction<T> };

/**
 * @deprecated
 */
export const storeObjectFromStore = <T>(
  store: [val: Store<T>, set: SetStoreFunction<T>],
): StoreObject<T> => {
  const [val, set] = store;
  return { val, set };
};

/**
 * @deprecated
 */
export type SetStoreFunctionProduce<T> = (f: (state: T) => void) => void;
/**
 * @deprecated
 */
export type StoreObjectProduce<T> = {
  value: Store<T>;
  update: (fn: (state: T) => void) => void;
};

/**
 * @deprecated
 */
export const storeObjectProduceFromStore = <T>(
  store: [val: Store<T>, set: SetStoreFunction<T>],
): StoreObjectProduce<T> => {
  const [value, set] = store;
  return {
    value,
    update: (f: (state: T) => void) => set(produce((s) => f(s))),
  };
};

/**
 * @deprecated
 */
export function produceUpdate<T, R = void>(
  state: StoreObjectProduce<T>,
  fn: (state: T) => R,
): R {
  let res!: R;
  state.update((state) => {
    res = fn(state);
  });
  return res;
}

/**
 * @deprecated
 */
export function storeUpdate<T, R = void>(
  set: SetStoreFunction<T>,
  fn: (state: T) => R,
): R {
  let res!: R;
  set(
    produce((state) => {
      res = fn(state);
    }),
  );
  return res;
}
