import { VoidComponent, Switch, Match } from "solid-js";

import cn from "~/lib/cn";

export type MouesButtonKind = "left" | "right" | "middle";

const MouseButton: VoidComponent<{
  kind: MouesButtonKind;
  down?: boolean;
}> = (props) => {
  return (
    <svg
      class={cn(
        "w-4 h-4 text-theme-border fill-theme-icon-base-fill stroke-theme-icon-base-stroke",
        props.down && "text-theme-text",
      )}
      viewBox="0 0 16 16"
      fill="none"
      stroke="none"
    >
      <rect width="10" height="14" x="3" y="1" rx="3" />
      <Switch>
        <Match when={props.kind === "left"}>
          <path fill="currentColor" d="M3 4c0-1.65685 1.34315-3 3-3h2v7H3V4Z" />
        </Match>
        <Match when={props.kind === "right"}>
          <path fill="currentColor" d="M8 1h2c1.6569 0 3 1.34315 3 3v4H8V1Z" />
        </Match>
        <Match when={props.kind === "middle"}>
          <rect width="2" height="7" x="7" y="1" fill="currentColor" rx="1" />
        </Match>
      </Switch>
    </svg>
  );
};

export type MovingButtonKind = "vertical" | "horizontal";

const MovingButton: VoidComponent<{
  kind: MovingButtonKind;
}> = (props) => {
  return (
    <svg
      class="w-4 h-4 text-theme-border fill-theme-icon-base-fill stroke-theme-icon-base-stroke"
      viewBox="0 0 16 16"
      fill="none"
      stroke="none"
    >
      <Switch>
        <Match when={props.kind === "vertical"}>
          <path d="M10 1c1.6569 0 3 1.34315 3 3v8c0 1.6569-1.3431 3-3 3H6c-1.65685 0-3-1.3431-3-3V4c0-1.65685 1.34315-3 3-3h4ZM6.39355 9.75c-.79639.00018-1.27263.886-.83398 1.5508l1.60547 2.4346c.39525.5988 1.27467.5988 1.66992 0l1.60544-2.4346c.4387-.6648-.0376-1.55062-.83395-1.5508h-3.2129Zm2.44141-7.48535c-.39525-.59887-1.27467-.59887-1.66992 0L5.55957 4.69922c-.43865.66479.03758 1.5506.83398 1.55078h3.2129c.79635-.00018 1.27265-.88599.83395-1.55078L8.83496 2.26465Z" />
        </Match>
        <Match when={props.kind === "horizontal"}>
          <path d="M10 1c1.6569 0 3 1.34315 3 3v8c0 1.6569-1.3431 3-3 3H6c-1.65685 0-3-1.3431-3-3V4c0-1.65685 1.34315-3 3-3h4ZM7.5 6.01953c-.0003-.88142-1.05814-1.33096-1.69336-.71973L3.74902 7.2793c-.40883.3934-.40883 1.048 0 1.4414l2.05762 1.9795c.63522.6112 1.69306.1617 1.69336-.71973V6.01953Zm2.6934-.71973c-.63526-.61123-1.6931-.16168-1.6934.71973v3.96094c.0003.88143 1.05814 1.33093 1.6934.71973l2.0576-1.9795c.4088-.3934.4088-1.048 0-1.4414l-2.0576-1.9795Z" />
        </Match>
      </Switch>
    </svg>
  );
};

export default Object.assign(MouseButton, {
  Moving: MovingButton,
});
