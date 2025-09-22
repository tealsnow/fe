import {
  Component,
  createEffect,
  createMemo,
  For,
  Index,
  ParentProps,
  Show,
  Switch,
} from "solid-js";
import { Option, Effect, Match } from "effect";

import { cn } from "~/lib/cn";

import { Icon, IconKind, icons } from "~/assets/icons";

import { useWindowContext } from "~/ui/WindowContext";
import Button from "~/ui/components/Button";

import { usePanelContext } from "./Context";
import {
  Workspace,
  updateSidebar,
  toggleSidebar,
  WorkspaceSidebars,
  WorkspaceSidebarSide,
  PanelNode,
  LeafContent,
  updateNode,
  selectTab,
  SplitAxis,
} from "./data";
import { Motion, Presence } from "solid-motionone";
import Percent from "~/lib/Percent";
import { createStore } from "solid-js/store";
import { MatchTag } from "~/lib/MatchTag";
import assert from "~/lib/assert";
import Integer from "~/lib/Integer";
import { MapOption } from "solid-effect";

export type ViewPanelTitlebarProps = ParentProps<{
  class?: string;
}>;
export const ViewPanelTitlebar: Component<ViewPanelTitlebarProps> = (props) => {
  return (
    <div
      class={cn(
        "flex flex-row h-6 w-full items-center border-theme-border border-b",
        props.class,
      )}
    >
      {props.children}
    </div>
  );
};

export type ViewWorkspaceTitlebarProps = {
  sidebars: () => WorkspaceSidebars;
};
export const ViewWorkspaceTitlebar: Component<ViewWorkspaceTitlebarProps> = (
  props,
) => {
  const ctx = usePanelContext();

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
    <ViewPanelTitlebar class="window-drag gap-2 border-0">
      <Icon icon={icons["fe"]} noDefaultStyles class="size-4 mx-1" />

      <div class="flex flex-row h-full items-center gap-0.5 -window-drag">
        <Index
          each={[
            {
              class: "rotate-90",
              get: () => props.sidebars().left.enabled,
              toggle: () =>
                ctx.setWorkspace("sidebars", (sidebars) =>
                  toggleSidebar({ sidebars, side: "left" }).pipe(
                    Effect.runSync,
                  ),
                ),
            },
            {
              class: "",
              get: () => props.sidebars().bottom.enabled,
              toggle: () =>
                ctx.setWorkspace("sidebars", (sidebars) =>
                  toggleSidebar({ sidebars, side: "bottom" }).pipe(
                    Effect.runSync,
                  ),
                ),
            },
            {
              class: "-rotate-90",
              get: () => props.sidebars().right.enabled,
              toggle: () =>
                ctx.setWorkspace("sidebars", (sidebars) =>
                  toggleSidebar({ sidebars, side: "right" }).pipe(
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
    </ViewPanelTitlebar>
  );
};

export type ViewWorkspaceProps = {};
export const ViewWorkspace: Component<ViewWorkspaceProps> = () => {
  const ctx = usePanelContext();

  const sidebars = createMemo(() => ctx.workspace.sidebars);

  const [sidebarSizes, setSidebarSizes] = createStore<
    Record<WorkspaceSidebarSide, Percent>
  >({
    left: Percent(0.25),
    right: Percent(0.25),
    bottom: Percent(0.25),
  });

  const sidebarStyles: Record<WorkspaceSidebarSide, string> = {
    left: "border-r",
    right: "border-l",
    bottom: "border-t",
  };

  const sidebarSizeType: Record<WorkspaceSidebarSide, "width" | "height"> = {
    left: "width",
    right: "width",
    bottom: "height",
  };

  const sidebarAxis: Record<WorkspaceSidebarSide, "x" | "y"> = {
    left: "x",
    right: "x",
    bottom: "y",
  };

  const sidebarAxisSign: Record<WorkspaceSidebarSide, "-" | "+"> = {
    left: "-",
    right: "+",
    bottom: "+",
  };

  const sidebarSize = (side: WorkspaceSidebarSide): string =>
    `${sidebarSizes[side] * 100}%`;

  type ViewSidebarProps = {
    side: WorkspaceSidebarSide;
  };
  const ViewSidebar: Component<ViewSidebarProps> = (props) => {
    return (
      <Presence initial={false}>
        <Show when={sidebars()[props.side].enabled}>
          <Motion.div
            class={cn(
              "relative flex border-theme-border overflow-none",
              sidebarStyles[props.side],
            )}
            style={{ [sidebarSizeType[props.side]]: sidebarSize(props.side) }}
            initial={{
              [sidebarAxis[props.side]]: `${sidebarAxisSign[props.side]}100%`,
            }}
            animate={{
              [sidebarAxis[props.side]]: 0,
            }}
            // @ts-expect-error 2322: false positive
            exit={{
              [sidebarAxis[props.side]]: `${sidebarAxisSign[props.side]}100%`,
              transition: { duration: 0.05, easing: "ease-out" },
            }}
            transition={{ duration: 0.05, easing: "ease-in" }}
          >
            <ViewPanelNode node={() => sidebars()[props.side].node} />
          </Motion.div>
        </Show>
      </Presence>
    );
  };

  return (
    <div class="flex flex-col grow">
      <ViewWorkspaceTitlebar sidebars={sidebars} />
      {/* border as an element to so you cannot drag the window by the border */}
      <div class="w-full h-[1px] bg-theme-border" />

      <div class="flex flex-row grow">
        <ViewSidebar side="left" />

        <div class="flex flex-col grow">
          <div class="flex grow">
            <ViewPanelNode node={() => ctx.workspace.root} />
          </div>

          <ViewSidebar side="bottom" />
        </div>

        <ViewSidebar side="right" />
      </div>
    </div>
  );
};

export type ViewPanelNodeProps = {
  node: () => PanelNode;
};
export const ViewPanelNode: Component<ViewPanelNodeProps> = (props) => {
  return (
    <Switch>
      <MatchTag on={props.node()} tag={"Split"}>
        {(split) => <ViewPanelNodeSplit split={split} />}
      </MatchTag>
      <MatchTag on={props.node()} tag={"Tabs"}>
        {(tabs) => <ViewPanelNodeTabs tabs={tabs} />}
      </MatchTag>
      <MatchTag on={props.node()} tag={"Leaf"}>
        {(leaf) => <ViewPanelNodeLeaf leaf={leaf} />}
      </MatchTag>
    </Switch>
  );
};

export type ViewPanelNodeSplitProps = {
  split: () => PanelNode.Split;
};
export const ViewPanelNodeSplit: Component<ViewPanelNodeSplitProps> = (
  props,
) => {
  // for why?
  // eslint-disable-next-line @typescript-eslint/explicit-function-return-type
  const axis = () => props.split().axis;

  const layoutSize: Record<SplitAxis, "height" | "width"> = {
    vertical: "height",
    horizontal: "width",
  };

  const layoutDirection: Record<SplitAxis, "flex-col" | "flex-row"> = {
    vertical: "flex-col",
    horizontal: "flex-row",
  };

  const layoutFullAxis: Record<SplitAxis, "w-full" | "h-full"> = {
    vertical: "w-full",
    horizontal: "h-full",
  };

  const borderSize: Record<SplitAxis, "h-[1px]" | "w-[1px]"> = {
    vertical: "h-[1px]",
    horizontal: "w-[1px]",
  };

  return (
    <div class={cn("flex grow", layoutDirection[axis()])}>
      <For each={props.split().children}>
        {(child, idx) => {
          return (
            <>
              <div
                class={cn("flex border-theme-border", layoutFullAxis[axis()])}
                style={{
                  [layoutSize[axis()]]: `${child.percent * 100}%`,
                }}
              >
                <ViewPanelNode node={() => child.node} />
              </div>
              <Show when={idx() !== props.split().children.length - 1}>
                <div
                  class={cn(
                    "bg-theme-border",
                    borderSize[axis()],
                    layoutFullAxis[axis()],
                  )}
                />
              </Show>
            </>
          );
        }}
      </For>
    </div>
  );
};

export type ViewPanelNodeTabsProps = {
  tabs: () => PanelNode.Tabs;
};
export const ViewPanelNodeTabs: Component<ViewPanelNodeTabsProps> = (props) => {
  const ctx = usePanelContext();

  createEffect(() => {
    if (props.tabs().children.some((child) => !PanelNode.$is("Leaf")(child)))
      throw new Error("Attempt to render tabs with non all leaf children");
  });

  const active = createMemo(() =>
    // for why?
    // eslint-disable-next-line solid/reactivity
    Option.map(props.tabs().active, (idx) => {
      const tab = props.tabs().children[idx];
      assert(PanelNode.$is("Leaf")(tab));
      return tab;
    }),
  );

  return (
    <div class="flex flex-col grow overflow-none">
      <ViewPanelTitlebar class="px-1">
        <For
          each={props
            .tabs()
            .children.filter((child) => PanelNode.$is("Leaf")(child))}
        >
          {(child, idx) => {
            const title = createMemo(() => ctx.getLeafContent(child.id).title);

            const selected = createMemo(() =>
              // for why?
              // eslint-disable-next-line solid/reactivity
              Option.map(props.tabs().active, (i) => i === idx()).pipe(
                Option.getOrElse(() => false),
              ),
            );

            return (
              <div
                class={cn(
                  "flex items-center h-full pt-0.5 px-0.5 gap-0.5 border-theme-border border-l last:border-r text-sm group cursor-pointer bg-theme-panel-tab-background-idle hover:bg-theme-panel-tab-background-active",
                  selected() && "bg-theme-panel-tab-background-active",
                )}
                onClick={() => {
                  ctx.setWorkspace("root", (root) =>
                    updateNode({
                      node: root,
                      match: (node) => node == props.tabs(),
                      fn: (tabs) => {
                        assert(PanelNode.$is("Tabs")(tabs));
                        return selectTab({
                          tabs,
                          index: Option.some(Integer(idx())),
                        }).pipe(Effect.runSync);
                      },
                    }).pipe(Effect.runSync),
                  );
                }}
              >
                {/* icon placeholder */}
                <div class="size-3.5" />

                {title()}

                <Button
                  as={Icon}
                  icon={icons["close"]}
                  variant="icon"
                  size="icon"
                  class="size-3.5 mb-0.5 opacity-0 group-hover:opacity-100"
                  noOnClickToOnMouseDown
                  onClick={() => {
                    // close tab
                  }}
                />
              </div>
            );
          }}
        </For>
      </ViewPanelTitlebar>
      <MapOption on={active()}>
        {(tab) => {
          const content = createMemo(() => ctx.getLeafContent(tab().id));
          return <ViewPanelNodeLeafContent content={content} />;
        }}
      </MapOption>
    </div>
  );
};

export type ViewPanelNodeLeafProps = {
  leaf: () => PanelNode.Leaf;
};
export const ViewPanelNodeLeaf: Component<ViewPanelNodeLeafProps> = (props) => {
  const ctx = usePanelContext();

  const content = createMemo(() => ctx.getLeafContent(props.leaf().id));

  return (
    <div class="flex flex-col grow overflow-none">
      <ViewPanelTitlebar class="text-sm px-1">
        {content().title}
      </ViewPanelTitlebar>
      <ViewPanelNodeLeafContent content={content} />
    </div>
  );
};

export type ViewPanelNodeLeafContentProps = {
  content: () => LeafContent;
};
export const ViewPanelNodeLeafContent: Component<
  ViewPanelNodeLeafContentProps
> = (props) => {
  return (
    <div class="flex grow overflow-auto">{props.content().render({})}</div>
  );
};

export namespace View {
  export type WorkspaceProps = ViewWorkspaceProps;
  export const Workspace = ViewWorkspace;

  export type PanelNodeProps = ViewPanelNodeProps;
  export const PanelNode = ViewPanelNode;

  export type PanelNodeSplitProps = ViewPanelNodeSplitProps;
  export const PanelNodeSplit = ViewPanelNodeSplit;

  export type PanelNodeTabsProps = ViewPanelNodeTabsProps;
  export const PanelNodeTabs = ViewPanelNodeTabs;

  export type PanelNodeLeafProps = ViewPanelNodeLeafProps;
  export const PanelNodeLeaf = ViewPanelNodeTabs;
}
export default View;
