export type IntrinsicDimension = "width" | "height";

export interface GetIntrinsicSizeOptions {
  dimension: IntrinsicDimension;
  lockCross?: boolean;
}

export function getIntrinsicSize(
  el: HTMLElement,
  { dimension, lockCross = false }: GetIntrinsicSizeOptions,
): number {
  const clone = el.cloneNode(true) as HTMLElement;
  const crossSize = lockCross
    ? dimension === "width"
      ? `${el.getBoundingClientRect().height}px`
      : `${el.getBoundingClientRect().width}px`
    : null;

  const style = [
    "position:absolute",
    "visibility:hidden",
    "left:-9999px",
    "top:-9999px",
    "overflow:visible",
    "box-sizing:border-box",
    dimension === "width"
      ? `width:auto;min-width:0;max-width:none${lockCross ? `;height:${crossSize}` : ""}`
      : `height:auto;min-height:0;max-height:none${lockCross ? `;width:${crossSize}` : ""}`,
  ].join(";");

  clone.style.cssText = style;
  document.body.appendChild(clone);
  const size = dimension === "width" ? clone.scrollWidth : clone.scrollHeight;
  document.body.removeChild(clone);
  return size;
}

export const getIntrinsicMinWidth = (el: HTMLElement) =>
  getIntrinsicSize(el, { dimension: "width", lockCross: true });

export const getIntrinsicMinHeight = (el: HTMLElement) =>
  getIntrinsicSize(el, { dimension: "height", lockCross: true });
