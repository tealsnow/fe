import { JSX, ValidComponent, mergeProps } from "solid-js";
import { Dynamic } from "solid-js/web";

const createElement = (
  tagName: ValidComponent,
  props: Record<string, unknown> | undefined,
  ...children: JSX.Element[]
): JSX.Element => {
  const finalProps = mergeProps(
    props || {},
    // Only add children if they exist to avoid unnecessary empty arrays
    children.length > 0
      ? { children: children.length === 1 ? children[0] : children }
      : {},
  );

  return Dynamic({ component: tagName, ...finalProps });
}
export default createElement;