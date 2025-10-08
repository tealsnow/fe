import { createSignal } from "solid-js";

export type ElementSize = {
  width: number;
  height: number;
};

export const createElementSize = <T extends HTMLElement>(): [
  () => ElementSize,
  (element: T) => void,
] => {
  const [size, setSize] = createSignal<ElementSize>({ width: 0, height: 0 });
  return [
    size,
    (element: T) => {
      new ResizeObserver(([entry]) => {
        const { width, height } = entry.contentRect;
        setSize({ width, height });
      }).observe(element);
    },
  ];
};
