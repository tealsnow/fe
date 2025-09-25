import { Component, Index, Switch } from "solid-js";

import { Icon, icons } from "~/assets/icons";

import { MatchTag } from "~/lib/MatchTag";

import Button from "~/ui/components/Button";

import { useStatusBarContext } from "./ContextProvider";
import { StatusBarItem } from "./Context";
export * from "./ContextProvider";
export * from "./Context";

export type StatusBarProps = {};
export const StatusBar: Component<StatusBarProps> = () => {
  const ctx = useStatusBarContext();

  return (
    <div class="flex flex-row w-full min-h-6 max-h-6 border-theme-border border-t items-center px-1 py-[1px] text-xs gap-1 overflow-hidden">
      <Index each={ctx.items().left}>
        {(id) => <RenderItem item={() => ctx.item_map()[id()]} />}
      </Index>
      <div class="flex grow h-full" />
      <div class="flex flex-row-reverse items-center gap-1">
        <Index each={ctx.items().right}>
          {(id) => <RenderItem item={() => ctx.item_map()[id()]} />}
        </Index>
      </div>
    </div>
  );
};

const RenderItem: Component<{ item: () => StatusBarItem }> = (props) => {
  return (
    <Switch>
      <MatchTag on={props.item()} tag="divider">
        {() => <div class="w-[1px] h-4 bg-theme-border" />}
      </MatchTag>
      <MatchTag on={props.item()} tag="text">
        {(text) => <p>{text().value()}</p>}
      </MatchTag>
      <MatchTag on={props.item()} tag="textButton">
        {(button) => (
          <Button
            variant="icon"
            size="small"
            class="border-transparent text-xs py-0"
            onClick={button().onClick}
          >
            {button().value()}
          </Button>
        )}
      </MatchTag>
      <MatchTag on={props.item()} tag="iconButton">
        {(button) => (
          <Button variant="icon" size="icon" onClick={button().onClick}>
            <Icon icon={icons[button().icon()]} />
          </Button>
        )}
      </MatchTag>
    </Switch>
  );
};

export default StatusBar;
