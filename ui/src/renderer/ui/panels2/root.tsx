import {
  Component,
  createMemo,
  createSignal,
  For,
  Index,
  JSXElement,
  Show,
} from "solid-js";
import { Presence, Motion } from "solid-motionone";

import { Option } from "effect";

import assert from "~/lib/assert";
import { cn } from "~/lib/cn";

import { Icon, IconKind } from "~/assets/icons";

import Button from "~/ui/components/Button";

import Panel from "./Panel";
import Render from "./Render";
import { createStore } from "solid-js/store";
import Percent from "~/lib/Percent";
import { useWindowContext } from "~/ui/WindowContext";

export const setupRoot = (): void => {
  const ctx = Panel.useContext();

  const [leftEnabled, setLeftEnabled] = createSignal(true);
  const [rightEnabled, setRightEnabled] = createSignal(true);
  const [bottomEnabled, setBottomEnabled] = createSignal(true);

  const centerNode = Panel.Node.DockSpace({
    layout: Panel.Node.DockSpaceLayout.Tabs(),
    parent: ctx.tree.root,
  });
  ctx.addNode(centerNode);

  type SlotKind = "left" | "right" | "bottom";

  const [slotSizes, setSlotSizes] = createStore<Record<SlotKind, Percent>>({
    left: Percent(0.25),
    right: Percent(0.25),
    bottom: Percent(0.25),
  });

  type MySlotProps = {
    class?: string;
    slots: Record<SlotKind, Panel.Node.DockSpaceLayout.Slot>;
    kind: SlotKind;
  };
  const MySlot: Component<MySlotProps> = (props) => {
    const styles: Record<SlotKind, string> = {
      left: "border-r",
      right: "border-l",
      bottom: "border-t",
    };

    const sizeType: Record<SlotKind, "width" | "height"> = {
      left: "width",
      right: "width",
      bottom: "height",
    };
    const sizeAxis: Record<SlotKind, "X" | "height"> = {
      left: "width",
      right: "width",
      bottom: "height",
    };

    // const sizes: Record<SlotKind, string> = {
    //   left: "25%",
    //   right: "25%",
    //   bottom: "25%",
    // };

    const size = (): string => `${slotSizes[props.kind] * 100}%`;
    const slot = createMemo(() => props.slots[props.kind]);

    return (
      <Presence initial={false}>
        <Show when={slot().enabled()}>
          <Motion.div
            class={cn(
              "relative flex border-theme-border",
              styles[props.kind],
              props.class,
            )}
            style={{ [sizeType[props.kind]]: size() }}
            initial={{
              // [props.kind]: `-${size()}`
              transform: `translateY(-${size()})`,
            }}
            animate={{
              // [props.kind]: 0
              transform: 0,
            }}
            exit={{
              // [props.kind]: `-${size()}`
              transform: `translateY(-${size()})`,
            }}
            transition={{ duration: 0.05, easing: "ease-out" }}
          >
            <Render.Slot slot={slot()} />
          </Motion.div>
        </Show>
      </Presence>
    );
  };

  type WindowButton = {
    icon: () => IconKind;
    onClick: () => void;
  };

  const windowCtx = useWindowContext();

  const windowButtons = (): WindowButton[] => [
    {
      icon: () => "window_minimize",
      onClick: windowCtx.minimize,
    },
    {
      icon: () =>
        windowCtx.maximized() ? "window_restore" : "window_maximize",
      onClick: windowCtx.toggleMaximize,
    },
    {
      icon: () => "close",
      onClick: windowCtx.close,
    },
  ];

  const root = Panel.Node.DockSpace({
    id: ctx.tree.root,
    layout: Panel.Node.DockSpaceLayout.Slotted({
      slots: [
        Panel.Node.DockSpaceLayout.Slot({
          name: "left",
          child: () => Option.none(),
          enabled: () => leftEnabled(),
        }),
        Panel.Node.DockSpaceLayout.Slot({
          name: "right",
          child: () => Option.none(),
          enabled: () => rightEnabled(),
        }),
        Panel.Node.DockSpaceLayout.Slot({
          name: "bottom",
          child: () => Option.none(),
          enabled: () => bottomEnabled(),
        }),
        Panel.Node.DockSpaceLayout.Slot({
          name: "center",
          child: () => Option.some(centerNode.id),
          enabled: () => true,
        }),
      ],
      addChild: Option.some((child) =>
        // just forward to the center node
        ctx.addChild({ dockSpace: centerNode.id, child: child.id }),
      ),
      layout: (props): JSXElement => {
        return (
          <div class="flex flex-col grow" data-panel-root={true}>
            <Render.Titlebar class="gap-2 window-drag">
              <Icon kind="fe" class="size-4" />
              <div class="flex flex-row gap-1 -window-drag">
                <Index
                  each={[
                    {
                      class: "rotate-90",
                      get: leftEnabled,
                      set: setLeftEnabled,
                    },
                    {
                      class: "",
                      get: bottomEnabled,
                      set: setBottomEnabled,
                    },
                    {
                      class: "-rotate-90",
                      get: rightEnabled,
                      set: setRightEnabled,
                    },
                  ]}
                >
                  {(bar) => (
                    <Button
                      class={bar().class}
                      size="icon"
                      variant="icon"
                      onClick={() => bar().set((b) => !b)}
                    >
                      <Icon
                        class="fill-transparent"
                        kind={
                          bar().get() ? "sidebar_enabled" : "sidebar_disabled"
                        }
                      />
                    </Button>
                  )}
                </Index>
              </div>

              <div class="grow" />

              <Button
                class="-window-drag"
                size="icon"
                variant="icon"
                onClick={() => ctx.toggleDebugSidePanel()}
                highlighted={ctx.showDebugSidePanel()}
              >
                ?
              </Button>

              <div class="flex h-full -window-drag">
                <For each={windowButtons()}>
                  {(button) => (
                    <div
                      class="hover:bg-theme-icon-base-fill
                      active:bg-theme-icon-active-fill inline-flex h-full w-8
                      items-center justify-center hover:cursor-pointer"
                      onClick={button.onClick}
                    >
                      <Icon kind={button.icon()} class="size-4" />
                    </div>
                  )}
                </For>
              </div>
            </Render.Titlebar>
            <div class="flex flex-col grow">
              <div class="flex flex-row grow">
                <MySlot slots={props.slots} kind="left" />

                <div class="flex grow">
                  <Render.Slot slot={props.slots["center"]} />
                </div>

                <MySlot slots={props.slots} kind="right" />
              </div>
              <MySlot slots={props.slots} kind="bottom" />
            </div>
          </div>
        );
      },
    }),
  });
  ctx.addNode(root);
  assert(Panel.Node.canBeRoot(root));
};
