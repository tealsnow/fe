export * from "./Context";
export * from "./ContextProvider";

import { Component, Index, Show, Switch } from "solid-js";

import { MatchTag } from "~/lib/MatchTag";

import Button from "~/ui/components/Button";
import Tooltip from "~/ui/components/Tooltip";

import { useContext } from "./ContextProvider";
import { BarItem } from "./Context";

export const StatusBar: Component<{}> = () => {
  const ctx = useContext();

  return (
    <div class="flex flex-row w-full min-h-6 max-h-6 border-t items-center px-1 py-[1px] text-xs gap-1">
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

const RenderItem: Component<{ item: () => BarItem }> = (props) => {
  return (
    <Tooltip>
      <Tooltip.Trigger>
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
                {button().icon({})}
              </Button>
            )}
          </MatchTag>
        </Switch>
      </Tooltip.Trigger>
      <Show when={props.item()["tooltip"] !== undefined}>
        <Tooltip.Content>
          {
            // @ts-expect-error 2339: we did just check
            props.item().tooltip()
          }
        </Tooltip.Content>
      </Show>
    </Tooltip>
  );
};
