import {
  Component,
  createMemo,
  ErrorBoundary,
  Index,
  JSXElement,
  lazy,
  ParentProps,
  Show,
  Suspense,
  Switch,
} from "solid-js";
import { MapOption } from "solid-effect";
import { Console, Effect, Option } from "effect";

import { MatchTag } from "~/lib/MatchTag";
import { cn } from "~/lib/cn";

import Panel from "./Panel";
import { create } from "node:domain";
import Button from "../components/Button";
import { Icon } from "~/assets/icons";
import Integer from "~/lib/Integer";

export type RenderSlotProps = {
  slot: Panel.Node.DockSpaceLayout.Slot;
  fallback?: JSXElement;
};
export const RenderSlot: Component<RenderSlotProps> = (props) => {
  return (
    <Show when={props.slot.enabled()}>
      <MapOption
        on={props.slot.child()}
        fallback={
          props.fallback ?? (
            <div class="flex flex-col grow items-center justify-center overflow-clip">
              <p>no panel</p>
              <p>(slot: '{props.slot.name}')</p>
            </div>
          )
        }
      >
        {(childId) => <RenderPanel id={childId} />}
      </MapOption>
    </Show>
  );
};

export type RenderPanelProps = {
  id: () => Panel.ID;
};
export const RenderPanel: Component<RenderPanelProps> = (props) => {
  return (
    <div class="flex grow relative overflow-hidden" data-render-panel={true}>
      <Switch>
        <MatchTag on={props.id()} tag="DockSpace">
          {(dockSpace) => <RenderDockSpace id={dockSpace} />}
        </MatchTag>
        <MatchTag on={props.id()} tag="Leaf">
          {(leaf) => <RenderLeaf id={leaf} />}
        </MatchTag>
      </Switch>

      {/*<Show when={panelHovered()}>
        <PanelDropOverlay panel={panel} />
      </Show>*/}
    </div>
  );
};

const getNode = <T extends Panel.ID["_tag"]>(
  ctx: Panel.Context,
  id: Extract<Panel.ID, { _tag: T }>,
): Extract<Panel.Node, { _tag: T }> => {
  return ctx.getNode(id).pipe(
    Effect.catchTag("PanelDoesNotExistInTreeError", (err) =>
      Effect.fail(`Attempt to render a non-existent panel: '${err}'`),
    ),
    Effect.runSync,
  );
};

export type RenderDockSpaceProps = {
  id: () => Panel.ID.DockSpace;
};
export const RenderDockSpace: Component<RenderDockSpaceProps> = (props) => {
  const ctx = Panel.useContext();

  const node = createMemo(() => getNode(ctx, props.id()));

  return (
    <Switch>
      <MatchTag on={node().layout} tag="Tabs">
        {(tabs) => <RenderDockSpaceTabs node={node} tabs={tabs} />}
      </MatchTag>
      <MatchTag on={node().layout} tag="Split">
        {(split) => <RenderDockSpaceSplit node={node} split={split} />}
      </MatchTag>
      <MatchTag on={node().layout} tag="Slotted">
        {(slotted) => <RenderDockSpaceSlotted slotted={slotted} />}
      </MatchTag>
    </Switch>
  );
};

export type RenderDockSpaceTabsProps = {
  node: () => Panel.Node.DockSpace;
  tabs: () => Panel.Node.DockSpaceLayout.Tabs;
};
export const RenderDockSpaceTabs: Component<RenderDockSpaceTabsProps> = (
  props,
) => {
  const ctx = Panel.useContext();

  return (
    <div
      class="flex flex-col grow overflow-hidden gap-0"
      data-render-dock-space={true}
    >
      <RenderTitlebar>
        <Index each={props.tabs().children}>
          {(childId, idx) => {
            const node = createMemo(() => getNode(ctx, childId()));

            const selected = (): boolean =>
              props.tabs().active.pipe(
                Option.map((active) => active === idx),
                Option.getOrElse(() => false),
              );

            return (
              <div
                class={cn(
                  "flex items-center justify-center h-full border-theme-border first:border-l border-r gap-1 px-1 leading-none bg-theme-panel-tab-background-idle hover:bg-theme-panel-tab-background-active group cursor-pointer",
                  selected() && "bg-theme-panel-tab-background-active",
                )}
                onMouseDown={() => {
                  ctx
                    .selectTab({
                      dockSpace: props.node().id,
                      index: Option.some(Integer(idx)),
                    })
                    .pipe(
                      Effect.tapError((error) =>
                        Console.error(
                          `Error when trying to select tab: ${error}`,
                        ),
                      ),
                      Effect.runSync,
                    );
                }}
              >
                <div class="size-3.5" />

                {node().title()}

                <Button
                  as={Icon}
                  kind="close"
                  variant="icon"
                  size="icon"
                  class="size-3.5 opacity-0 group-hover:opacity-100"
                  noOnClickToOnMouseDown
                  onClick={() => {
                    // TODO: close
                  }}
                />
              </div>
            );
          }}
        </Index>
      </RenderTitlebar>
      <MapOption on={props.tabs().active}>
        {(index) => {
          const tab = getNode(ctx, props.tabs().children[index()]);

          return <RenderLeafContent node={() => tab} />;
        }}
      </MapOption>
    </div>
  );
};

export type RenderDockSpaceSplitProps = {
  node: () => Panel.Node.DockSpace;
  split: () => Panel.Node.DockSpaceLayout.Split;
};
export const RenderDockSpaceSplit: Component<RenderDockSpaceSplitProps> = (
  props,
) => {
  return <>TODO: Split</>;
};

export type RenderDockSpaceSlottedProps = {
  slotted: () => Panel.Node.DockSpaceLayout.Slotted;
};
export const RenderDockSpaceSlotted: Component<RenderDockSpaceSlottedProps> = (
  props,
) => {
  return (
    <div
      class="flex grow overflow-hidden"
      data-render-dock-space-slotted={true}
    >
      {props.slotted().layout({ slots: props.slotted().slots })}
    </div>
  );
};

export type RenderLeafProps = {
  id: () => Panel.ID.Leaf;
};
export const RenderLeaf: Component<RenderLeafProps> = (props) => {
  return <>TODO: leaf</>;
};

export type RenderTitlebarProps = ParentProps<{
  class?: string;
}>;
export const RenderTitlebar: Component<RenderTitlebarProps> = (props) => {
  return (
    <div
      class={cn(
        "flex flex-row px-1 min-h-6 max-h-6 w-full border-b border-theme-border items-center text-xs",
        props.class,
      )}
      data-render-titlebar={true}
    >
      {props.children}
    </div>
  );
};

export type RenderLeafContentProps = {
  node: () => Panel.Node.Leaf;
};
export const RenderLeafContent: Component<RenderLeafContentProps> = (props) => {
  return (
    <ErrorBoundary
      fallback={(error, reset) => (
        <div class="flex flex-col grow items-center justify-center gap-2">
          <p>something went wrong: '{error.message}'</p>
          <Button color="green" onClick={reset}>
            Try Again
          </Button>
        </div>
      )}
    >
      <Suspense
        fallback=<div class="flex grow items-center justify-center">
          Loading...
        </div>
      >
        <div
          class="flex flex-col grow overflow-auto"
          data-render-leaf-content={true}
        >
          {lazy(props.node().content)({})}
        </div>
      </Suspense>
    </ErrorBoundary>
  );
};

export namespace Render {
  export type SlotProps = RenderSlotProps;
  export const Slot = RenderSlot;
  export type PanelProps = RenderPanelProps;
  export const Panel = RenderPanel;
  export type DockSpaceProps = RenderDockSpaceProps;
  export const DockSpace = RenderDockSpace;
  export type LeafProps = RenderLeafProps;
  export const Leaf = RenderLeaf;
  export type DockSpaceTabsProps = RenderDockSpaceTabsProps;
  export const DockSpaceTabs = RenderDockSpaceTabs;
  export type DockSpaceSplitProps = RenderDockSpaceSplitProps;
  export const DockSpaceSplit = RenderDockSpaceSplit;
  export type DockSpaceSlottedProps = RenderDockSpaceSlottedProps;
  export const DockSpaceSlotted = RenderDockSpaceSlotted;
  export type TitlebarProps = RenderTitlebarProps;
  export const Titlebar = RenderTitlebar;
  export type LeafContentProps = RenderLeafContentProps;
  export const LeafContent = RenderLeafContent;
}
export default Render;
