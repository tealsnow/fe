import { createEffect, createSignal, onCleanup, Accessor } from "solid-js";

export const createBoolTimeout = (
  source: Accessor<boolean>,
  delay: number,
): Accessor<boolean> => {
  const [delayed, setDelayed] = createSignal(false);
  let timer: number | undefined;

  createEffect(() => {
    if (source()) {
      timer = window.setTimeout(() => setDelayed(true), delay);
    } else {
      clearTimeout(timer);
      setDelayed(false);
    }
  });

  onCleanup(() => clearTimeout(timer));
  return delayed;
};

export default createBoolTimeout;
