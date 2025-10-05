/* @refresh reload */

import {
  Component,
  For,
  onMount,
  Show,
  onCleanup,
  createSignal,
  Setter,
  Accessor,
  createMemo,
} from "solid-js";
import { render as solidRender } from "solid-js/web";
import { Option, Effect } from "effect";

import {
  draggable,
  dropTargetForElements,
} from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { setCustomNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/set-custom-native-drag-preview";
import { pointerOutsideOfPreview } from "@atlaskit/pragmatic-drag-and-drop/element/pointer-outside-of-preview";
import { combine as pdndCombine } from "@atlaskit/pragmatic-drag-and-drop/combine";
import { CleanupFn } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";

import { PolymorphicCallbackProps } from "@kobalte/core/polymorphic";
import {
  TooltipTriggerProps,
  TooltipTriggerRenderProps,
} from "@kobalte/core/tooltip";

import { Icon, icons } from "~/assets/icons";

import cn from "~/lib/cn";
import Integer from "~/lib/Integer";
import { UpdateFn } from "~/lib/UpdateFn";
import * as Notif from "~/lib/Notif";

import Button, { ButtonProps } from "~/ui/components/Button";
import Tooltip from "~/ui/components/Tooltip";

import { useContext } from "../Context";
import { PanelNode, SplitAxis, Leaf, tabsSelect } from "../data";

import PanelTitlebar from "./PanelTitlebar";
import {
  DragDataForTab,
  DropSide,
  DropTargetDataForTab,
  DropTargetSplitTabs,
} from "./dnd";
import LeafContent from "./LeafContent";
import RenderDropPoint from "./RenderDropPoint";

export const ViewPanelNodeTabs: Component<{
  tabs: () => PanelNode.Tabs;
  updateTabs: UpdateFn<PanelNode.Tabs>;
  parentSplitAxis: () => Option.Option<SplitAxis>;
}> = (props) => {
  const ctx = useContext();

  const active = (): Option.Option<Leaf> =>
    // false positive
    // eslint-disable-next-line solid/reactivity
    Option.flatMap(props.tabs().active, (idx) => {
      if (idx >= props.tabs().children.length) return Option.none();
      return Option.some(props.tabs().children[idx]);
    });

  const [hasDrop, setHasDrop] = createSignal(false);

  let tabDropRef!: HTMLDivElement;
  onMount(() => {
    const cleanup = dropTargetForElements({
      element: tabDropRef,

      getData: () =>
        DropTargetDataForTab({
          tabs: props.tabs(),
          updateTabs: props.updateTabs,
          idx: Option.none(),
        }),

      canDrop: ({ source }) => {
        if (DragDataForTab.$is(source.data)) return true;

        return false;
      },

      onDragEnter: () => setHasDrop(true),
      onDragLeave: () => setHasDrop(false),
      onDrop: () => setHasDrop(false),
    });
    onCleanup(() => cleanup());
  });

  const activeTabContent = (): Component<{}> =>
    active().pipe(
      Option.flatMap(({ id }) =>
        ctx.getLeaf(id).pipe(Option.map((content) => content.render)),
      ),
      Option.getOrElse(() => () => (
        <div class="flex w-full h-full items-center justify-center">
          <p>no tab selected</p>
        </div>
      )),
    );

  const [tabHovered, setTabHovered] = createSignal(false);

  let ref!: HTMLDivElement;

  onMount(() => {
    const cleanup = dropTargetForElements({
      element: ref,

      onDragStart: ({ source }) => {
        if (DragDataForTab.$is(source.data)) setTabHovered(true);
      },
      onDragEnter: ({ source }) => {
        if (DragDataForTab.$is(source.data)) setTabHovered(true);
      },
      onDragLeave: ({ source }) => {
        if (DragDataForTab.$is(source.data)) setTabHovered(false);
      },
      onDrop: () => setTabHovered(false),
    });
    onCleanup(() => cleanup());
  });

  const notifCtx = Notif.useContext();

  return (
    <div
      ref={ref}
      class="flex flex-col relative w-full h-full"
      data-tabs-panel-root
    >
      <PanelTitlebar class="px-1">
        <For each={props.tabs().children}>
          {(child, idx) => (
            <ViewTabHandle
              tabs={props.tabs}
              updateTabs={props.updateTabs}
              active={() => props.tabs().active}
              idx={() => Integer(idx())}
              leaf={() => child}
              onClick={() => {
                // false positive
                // eslint-disable-next-line solid/reactivity
                props.updateTabs((tabs) =>
                  tabsSelect({
                    tabs,
                    index: Option.some(Integer(idx())),
                  }).pipe(Effect.runSync),
                );
              }}
              onCloseClick={() => {
                console.warn("TODO: tab close click");
                notifCtx.notify("TODO: close tab", { level: "warning" });
              }}
            />
          )}
        </For>

        <div
          ref={tabDropRef}
          class={cn(
            "grow h-full min-w-5",
            hasDrop() && "bg-theme-panel-tab-background-drop-target",
          )}
          onClick={() =>
            props.updateTabs((tabs) =>
              tabsSelect({
                tabs,
                index: Option.none(),
              }).pipe(Effect.runSync),
            )
          }
        />

        <div class="flex items-center border-l h-full">
          <Tooltip>
            <Tooltip.Trigger
              aria-describedby=""
              as={(
                props: PolymorphicCallbackProps<
                  ButtonProps,
                  TooltipTriggerProps,
                  TooltipTriggerRenderProps
                >,
              ) => <Button as={Icon} icon={icons["add"]} {...props} />}
              variant="icon"
              size="icon"
              class="p-1 ml-1"
              onClick={() => {
                console.warn("TODO: new tab");
                notifCtx.notify("TODO: new tab", { level: "warning" });
              }}
            />
            <Tooltip.Content>new tab</Tooltip.Content>
          </Tooltip>
        </div>
      </PanelTitlebar>

      <LeafContent render={() => activeTabContent()} />

      <Show when={tabHovered()}>
        <TabsDropOverlay
          tabs={props.tabs}
          updateTabs={props.updateTabs}
          parentSplitAxis={props.parentSplitAxis}
        />
      </Show>
    </div>
  );
};

const TabsDropOverlay: Component<{
  tabs: () => PanelNode.Tabs;
  updateTabs: UpdateFn<PanelNode.Tabs>;
  parentSplitAxis: () => Option.Option<SplitAxis>;
}> = (props) => {
  let centerRef!: HTMLDivElement;
  const [centerHovered, setCenterHovered] = createSignal(false);
  onMount(() => {
    const cleanup = dropTargetForElements({
      element: centerRef,

      getData: () =>
        DropTargetDataForTab({
          tabs: props.tabs(),
          updateTabs: props.updateTabs,
          idx: Option.none(),
        }),

      canDrop: ({ source }) => {
        if (DragDataForTab.$is(source.data)) return true;
        return false;
      },

      onDragEnter: () => setCenterHovered(true),
      onDragLeave: () => setCenterHovered(false),
      onDrop: () => setCenterHovered(false),
    });
    onCleanup(() => cleanup());
  });

  type SideDropInfo = {
    ref: HTMLDivElement | undefined;
    hovered: Accessor<boolean>;
    setHovered: Setter<boolean>;
    side: DropSide;
  };

  const sideInfos: Record<DropSide, SideDropInfo> = DropSide.reduce(
    (acc, side) => {
      const [hovered, setHovered] = createSignal(false);
      acc[side] = {
        ref: undefined,
        hovered,
        setHovered,
        side,
      };
      return acc;
    },
    {} as Record<DropSide, SideDropInfo>,
  );

  onMount(() => {
    const cleanups: CleanupFn[] = [];

    const setupDropTarget = (info: SideDropInfo): void => {
      if (!info.ref) return;
      const cleanup = dropTargetForElements({
        element: info.ref,

        getData: () =>
          DropTargetSplitTabs({
            tabs: props.tabs(),
            side: info.side,
          }),

        canDrop: ({ source }) => {
          if (DragDataForTab.$is(source.data)) return true;
          return false;
        },

        onDragEnter: () => info.setHovered(true),
        onDragLeave: () => info.setHovered(false),
        onDrop: () => info.setHovered(false),
      });
      cleanups.push(cleanup);
    };

    for (const side of DropSide) {
      const info = sideInfos[side];
      setupDropTarget(info);
    }

    onCleanup(() => {
      for (const cleanup of cleanups) cleanup();
    });
  });

  const sidePositions: Record<DropSide, string> = {
    left: "col-2 row-3",
    right: "col-4 row-3",
    top: "col-3 row-2",
    bottom: "col-3 row-4",
  };

  const sideIconClass: Record<DropSide, string> = {
    left: "rotate-90",
    right: "-rotate-90",
    top: "rotate-180",
    bottom: "",
  };

  const RenderSideDropPoint: Component<{ side: DropSide }> = (props) => {
    return (
      <RenderDropPoint
        ref={sideInfos[props.side].ref}
        icon="dnd_tabs_side"
        tooltip={`create split to the ${props.side}`}
        hovered={sideInfos[props.side].hovered}
        class={sidePositions[props.side]}
        iconClass={sideIconClass[props.side]}
      />
    );
  };

  return (
    <div
      class={cn(
        "absolute top-0 bottom-0 left-0 right-0 z-10",
        "grid",
        "grid-cols-[1fr_36px_36px_36px_1fr]",
        "grid-rows-[1fr_36px_36px_36px_1fr]",
        "pointer-events-none",
      )}
    >
      <RenderDropPoint
        ref={centerRef}
        icon="dnd_tabs_middle"
        tooltip="append tab"
        hovered={centerHovered}
        class="col-3 row-3"
      />

      <Show
        when={
          props
            .parentSplitAxis()
            .pipe(Option.getOrElse<SplitAxis>(() => "vertical")) === "vertical"
        }
      >
        <RenderSideDropPoint side="left" />
        <RenderSideDropPoint side="right" />
      </Show>
      <Show
        when={
          props
            .parentSplitAxis()
            .pipe(Option.getOrElse<SplitAxis>(() => "horizontal")) ===
          "horizontal"
        }
      >
        <RenderSideDropPoint side="top" />
        <RenderSideDropPoint side="bottom" />
      </Show>
    </div>
  );
};

export const ViewTabHandle: Component<{
  tabs: () => PanelNode.Tabs;
  updateTabs: UpdateFn<PanelNode.Tabs>;
  active: () => Option.Option<Integer>;
  idx: () => Integer;
  leaf: () => Leaf;
  onClick: () => void;
  onCloseClick: () => void;
}> = (props) => {
  const ctx = useContext();

  const selected = (): boolean =>
    // false positive
    // eslint-disable-next-line solid/reactivity
    Option.map(props.active(), (i) => i === props.idx()).pipe(
      Option.getOrElse(() => false),
    );

  const [dragging, setDragging] = createSignal(false);
  const [hasDrop, setHasDrop] = createSignal(false);

  const titleAndTooltip = createMemo((): { title: string; tooltip: string } =>
    Option.getOrElse(
      Option.map(ctx.getLeaf(props.leaf().id), ({ title, tooltip }) => ({
        title,
        tooltip,
      })),
      () => ({ title: "<none leaf>", tooltip: "leaf has no content" }),
    ),
  );

  let ref!: HTMLDivElement;
  onMount(() => {
    const cleanup = pdndCombine(
      draggable({
        element: ref,

        getInitialData: () =>
          DragDataForTab({
            tabs: props.tabs(),
            updateTabs: props.updateTabs,
            leaf: props.leaf(),
            idx: props.idx(),
          }),

        onGenerateDragPreview: ({ nativeSetDragImage }) => {
          setDragging(true);

          setCustomNativeDragPreview({
            getOffset: pointerOutsideOfPreview({
              x: "calc(var(--spacing) * 2)",
              y: "calc(var(--spacing) * 2)",
            }),
            render: ({ container }) =>
              solidRender(
                () => (
                  <ViewTabHandleImpl
                    class="h-6 border text-theme-text bg-theme-background opacity-75"
                    title={() => titleAndTooltip().title}
                    tooltip={() => titleAndTooltip().tooltip}
                  />
                ),
                container,
              ),
            nativeSetDragImage,
          });
        },
        onDrop: () => setDragging(false),
      }),
      dropTargetForElements({
        element: ref,

        getData: () =>
          DropTargetDataForTab({
            tabs: props.tabs(),
            updateTabs: props.updateTabs,
            idx: Option.some(props.idx()),
          }),

        canDrop: ({ source }) => {
          if (DragDataForTab.$is(source.data)) return true;

          return false;
        },

        onDragEnter: () => setHasDrop(true),
        onDragLeave: () => setHasDrop(false),
        onDrop: () => setHasDrop(false),
      }),
    );
    onCleanup(() => cleanup());
  });

  return (
    <ViewTabHandleImpl
      ref={ref}
      class={cn(
        "relative first:border-l border-r cursor-pointer hover:bg-theme-panel-tab-background-active transition-colors duration-100",
        selected() && "bg-theme-panel-tab-background-active",
        dragging() && "text-transparent",
        hasDrop() && "bg-theme-panel-tab-background-drop-target",
      )}
      title={() => titleAndTooltip().title}
      tooltip={() => titleAndTooltip().tooltip}
      onClick={() => {
        if (selected()) return;
        props.onClick();
      }}
      onCloseClick={props.onCloseClick}
    />
  );
};

const ViewTabHandleImpl: Component<{
  ref?: HTMLDivElement;
  class?: string;
  title: () => string;
  tooltip: () => string;
  onClick?: () => void;
  onCloseClick?: () => void;
}> = (props) => {
  return (
    <Tooltip>
      <Tooltip.Trigger
        as="div"
        ref={props.ref}
        class={cn(
          "flex items-center h-full pt-0.5 px-0.5 gap-0.5 text-sm bg-theme-panel-tab-background-idle group overflow-clip whitespace-nowrap",
          props.class,
        )}
        onClick={() => props.onClick?.()}
      >
        {/* icon placeholder */}
        <div class="size-3.5" />

        {props.title()}

        <Tooltip>
          <Tooltip.Trigger
            aria-describedby=""
            as={(
              props: PolymorphicCallbackProps<
                ButtonProps,
                TooltipTriggerProps,
                TooltipTriggerRenderProps
              >,
            ) => <Button as={Icon} icon={icons["close"]} {...props} />}
            variant="icon"
            size="icon"
            class="size-3.5 mb-0.5 opacity-0 group-hover:opacity-100"
            noOnClickToOnMouseDown
            onClick={(event) => {
              if (!props.onCloseClick) return;
              event.stopPropagation();
              props.onCloseClick();
            }}
          />
          <Tooltip.Content>close tab</Tooltip.Content>
        </Tooltip>
      </Tooltip.Trigger>
      <Show when={props.tooltip().length !== 0}>
        <Tooltip.Content>{props.tooltip()}</Tooltip.Content>
      </Show>
    </Tooltip>
  );
};

export default ViewPanelNodeTabs;
