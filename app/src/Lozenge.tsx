import clsx from "clsx";
import { JSX, mergeProps } from "solid-js";
import { css } from "solid-styled-components";
import { ColorKind } from "./Theme";

export type LozengeProps = JSX.HTMLAttributes<HTMLButtonElement> & {
  color: ColorKind;
  interactive?: boolean;
  highlighted?: boolean;
  disabled?: boolean;
};

const Lozenge = (props_: LozengeProps) => {
  const props = mergeProps(
    { interactive: false, highlighted: false, disabled: false },
    props_,
  );
  const { color, interactive, highlighted, ...forwardProps } = props_;

  return (
    <button
      {...forwardProps}
      class={clsx(
        props.class,
        "inline-block px-0.5 py-1 size-fit border-2 text-center content-center",
        css`
          ${props.disabled
            ? ""
            : `background: ${`var(--theme-colors-${props.color}-${props.highlighted ? "base" : "background"})`};`}
          border-color: ${`var(--theme-colors-${props.color}-border)`};
        `,
        props.interactive &&
          !props.disabled && [
            "transition duration-150 underline",
            css`
              &:hover {
                background: ${`var(--theme-colors-${props.color}-base)`} !important;
              }
            `,
          ],
      )}
    >
      {props.children}
    </button>
  );
};

export default Lozenge;
