import { Component, For, Index, Show, VoidComponent } from "solid-js";
import { Option, Effect, Match } from "effect";

import { Icon, IconKind, icons } from "~/assets/icons";

import { cn } from "~/lib/cn";

import { useWindowContext } from "~/ui/Window";
import Button from "~/ui/components/Button";

import { useContext } from "../Context";
import {
  WorkspaceSidebars,
  WorkspaceSidebarSide,
  SplitAxis,
  sidebarToggle,
} from "../data";

import PanelTitlebar from "./PanelTitlebar";
import { WorkspaceResizeHandle } from "./ResizeHandle";
import ViewPanelNode from "./PanelNode";

export const Workspace: VoidComponent = () => {
  const ctx = useContext();

  const sidebars = (): WorkspaceSidebars => ctx.workspace.sidebars;

  const sidebarSize = (side: WorkspaceSidebarSide): string =>
    `${sidebars()[side].size * 100}%`;

  const ViewSidebar: Component<{
    side: WorkspaceSidebarSide;
  }> = (props) => {
    const sizeType: Record<WorkspaceSidebarSide, "width" | "height"> = {
      left: "width",
      right: "width",
      bottom: "height",
    };

    const parentAxis: Record<WorkspaceSidebarSide, SplitAxis> = {
      left: "horizontal",
      right: "horizontal",
      bottom: "vertical",
    };

    return (
      <Show when={sidebars()[props.side].enabled}>
        <div
          data-sidebar-root
          data-sidebar-side={props.side}
          class="relative flex border-theme-border"
          style={{
            [sizeType[props.side]]: sidebarSize(props.side),
          }}
        >
          <ViewPanelNode
            node={() => sidebars()[props.side].node}
            updateNode={(fn) =>
              // false positive
              // eslint-disable-next-line solid/reactivity
              ctx.setWorkspace("sidebars", (sidebars) => ({
                ...sidebars,
                [props.side]: {
                  ...sidebars[props.side],
                  node: fn(sidebars[props.side].node),
                },
              }))
            }
            parentSplitAxis={() => Option.some(parentAxis[props.side])}
          />
        </div>
      </Show>
    );
  };

  const SidebarResizeHandle: Component<{
    side: WorkspaceSidebarSide;
  }> = (props) => {
    const axis: Record<WorkspaceSidebarSide, SplitAxis> = {
      left: "horizontal",
      right: "horizontal",
      bottom: "vertical",
    };
    const sign: Record<WorkspaceSidebarSide, "+" | "-"> = {
      left: "+",
      right: "-",
      bottom: "-",
    };

    return (
      <Show when={sidebars()[props.side].enabled}>
        <WorkspaceResizeHandle
          axis={axis[props.side]}
          size={sidebars()[props.side].size}
          updateSize={(size) =>
            // false positive
            // eslint-disable-next-line solid/reactivity
            ctx.setWorkspace("sidebars", (sidebars) => ({
              ...sidebars,
              [props.side]: {
                ...sidebars[props.side],
                size,
              },
            }))
          }
          sign={sign[props.side]}
        />
      </Show>
    );
  };

  return (
    <div class="flex flex-col w-full h-full" data-workspace-root>
      <WorkspaceTitlebar sidebars={sidebars} />
      {/* border as an element to so you cannot drag the window by the border */}
      <div class="w-full min-h-[1px] max-h-[1px] bg-theme-border" />

      <div class="flex flex-row w-full h-full">
        <ViewSidebar side="left" />
        <SidebarResizeHandle side="left" />

        <div
          class="flex flex-col"
          style={{
            width: `${
              (1 -
                ((sidebars().left.enabled ? sidebars().left.size : 0) +
                  (sidebars().right.enabled ? sidebars().right.size : 0))) *
              100
            }%`,
          }}
        >
          <div
            class="flex w-full"
            style={{
              height: `${
                (1 - (sidebars().bottom.enabled ? sidebars().bottom.size : 0)) *
                100
              }%`,
            }}
          >
            <ViewPanelNode
              node={() => ctx.workspace.root}
              updateNode={(fn) => ctx.setWorkspace("root", fn)}
              parentSplitAxis={() => Option.none()}
            />
          </div>

          <SidebarResizeHandle side="bottom" />
          <ViewSidebar side="bottom" />
        </div>

        <SidebarResizeHandle side="right" />
        <ViewSidebar side="right" />
      </div>
    </div>
  );
};

export const WorkspaceTitlebar: Component<{
  sidebars: () => WorkspaceSidebars;
}> = (props) => {
  const ctx = useContext();

  type WindowButton = {
    icon: () => IconKind;
    onClick: () => void;
  };

  const windowCtx = useWindowContext();

  type WindowIconKind = "close" | "maximize" | "restore" | "minimize";
  type WindowIconRecord = Record<WindowIconKind, IconKind>;
  type WindowIcons = {
    record: WindowIconRecord;
    noDefaultStyles: boolean;
    class: string | undefined;
    iconClass: string | undefined;
  };

  const windowIcons = Match.value(window.api.platform).pipe(
    Match.withReturnType<WindowIcons>(),
    Match.when("Linux", () => ({
      record: {
        close: "adwaita_window_close",
        maximize: "adwaita_window_maximize",
        restore: "adwaita_window_restore",
        minimize: "adwaita_window_minimize",
      },
      class: "size-6 rounded-xl group hover:bg-transparent",
      iconClass:
        "stroke-theme-icon-base-transparent fill-theme-icon-base-stroke group-hover:bg-theme-icon-base-fill rounded-xl",
      noDefaultStyles: false,
    })),
    Match.orElse(() => ({
      record: {
        close: "close",
        maximize: "window_maximize",
        restore: "window_restore",
        minimize: "window_minimize",
      },
      class: "h-full w-10 rounded-none",
      iconClass: undefined,
      noDefaultStyles: false,
    })),
  );

  const windowButtons = (): WindowButton[] => [
    {
      icon: () => windowIcons.record.minimize,
      onClick: windowCtx.minimize,
    },
    {
      icon: () =>
        windowCtx.maximized()
          ? windowIcons.record.restore
          : windowIcons.record.maximize,
      onClick: windowCtx.toggleMaximize,
    },
    {
      icon: () => windowIcons.record.close,
      onClick: windowCtx.close,
    },
  ];

  return (
    <PanelTitlebar class="window-drag gap-2 border-0">
      <Icon icon={icons["fe"]} noDefaultStyles class="size-4 mx-1" />

      <div class="flex flex-row h-full items-center gap-0.5 -window-drag">
        <Index
          each={[
            {
              class: "rotate-90",
              get: () => props.sidebars().left.enabled,
              toggle: () =>
                ctx.setWorkspace("sidebars", (sidebars) =>
                  sidebarToggle({ sidebars, side: "left" }).pipe(
                    Effect.runSync,
                  ),
                ),
            },
            {
              class: "",
              get: () => props.sidebars().bottom.enabled,
              toggle: () =>
                ctx.setWorkspace("sidebars", (sidebars) =>
                  sidebarToggle({ sidebars, side: "bottom" }).pipe(
                    Effect.runSync,
                  ),
                ),
            },
            {
              class: "-rotate-90",
              get: () => props.sidebars().right.enabled,
              toggle: () =>
                ctx.setWorkspace("sidebars", (sidebars) =>
                  sidebarToggle({ sidebars, side: "right" }).pipe(
                    Effect.runSync,
                  ),
                ),
            },
          ]}
        >
          {(bar) => (
            <Button
              as={Icon}
              icon={icons[bar().get() ? "sidebar_enabled" : "sidebar_disabled"]}
              class={cn("fill-transparent", bar().class)}
              size="icon"
              variant="icon"
              onClick={() => bar().toggle()}
            />
          )}
        </Index>
      </div>

      <div class="grow" />

      <div class="flex h-full -window-drag">
        <For each={windowButtons()}>
          {(button) => (
            <Button
              variant="icon"
              size="icon"
              class={windowIcons.class}
              noOnClickToOnMouseDown
              onClick={button.onClick}
            >
              <Icon
                icon={icons[button.icon()]}
                noDefaultStyles={windowIcons.noDefaultStyles}
                class={windowIcons.iconClass}
              />
            </Button>
          )}
        </For>
      </div>
    </PanelTitlebar>
  );
};

export default Workspace;
