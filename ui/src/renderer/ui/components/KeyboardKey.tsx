import { Show, VoidComponent } from "solid-js";

import cn from "~/lib/cn";

const KeyboardKey: VoidComponent<{
  text: string;
  long?: boolean;
  down?: boolean;
  textOffset?: number;
}> = (props) => {
  return (
    <svg
      class={cn(
        "w-4 h-4 fill-theme-icon-base-fill stroke-theme-icon-base-stroke",
        props.long && "w-8",
      )}
      viewBox={props.long ? "0 0 32 16" : "0 0 16 16"}
      fill="none"
      stroke="none"
    >
      <Show when={!props.down}>
        <rect
          width={props.long ? "31" : "15"}
          height="15"
          x=".5"
          y=".5"
          rx="1.5"
        />
      </Show>
      <rect
        width={props.long ? "31" : "15"}
        height="12"
        x=".5"
        y={props.down ? "3.5" : ".5"}
        rx="1.5"
      />
      <text
        x={props.long ? "16" : "8"}
        y={(props.down ? 11 : 8) + (props.textOffset ?? 0)}
        text-anchor="middle"
        dominant-baseline="middle"
        fill="currentColor"
        stroke="none"
        class="font-mono"
        font-size="9px"
        font-weight="500"
      >
        {props.text}
      </text>
    </svg>
  );
};

export const Shift: VoidComponent<{ down?: boolean }> = (props) => (
  <KeyboardKey text="Shift" long down={props.down} />
);
export const Ctrl: VoidComponent<{ down?: boolean }> = (props) => (
  <KeyboardKey text="Ctrl" long down={props.down} />
);
export const Alt: VoidComponent<{ down?: boolean }> = (props) => (
  <KeyboardKey text="Alt" long down={props.down} />
);
export const Space: VoidComponent<{ down?: boolean }> = (props) => (
  <KeyboardKey text="Space" long down={props.down} textOffset={-1} />
);

export default Object.assign(KeyboardKey, {
  Shift,
  Ctrl,
  Alt,
  Space,
});
