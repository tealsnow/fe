import { getCurrentWindow } from "@tauri-apps/api/window";
import { createEffect, createSignal, For, onMount, Show } from "solid-js";
import { Icon, IconKind } from "./assets/icons";
import {
  closestCenter,
  createDraggable,
  createDroppable,
  DragDropProvider,
  DragDropSensors,
  DragOverlay,
} from "@thisbeyond/solid-dnd";
import { statusBar } from "./StatusBar";
import { Workspace } from "./Workspace";
import clsx from "clsx";

declare module "solid-js" {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace JSX {
    interface Directives {
      draggable: {};
      droppable: {};
    }
  }
}

type TitlebarProps = {
  workspaces: Workspace[];
  activeIndex: number | undefined;
  onReorder: (oldIdx: number, newIdx: number) => void;
  onActiveIndexChange: (index: number) => void;
  onCloseClick: (index: number) => void;
  onNewClick: () => void;
};

type NarrowedWindow = {
  minimize: () => Promise<void>;
  toggleMaximize: () => Promise<void>;
  close: () => Promise<void>;
};

// @TODO: when there is overflow scroll to the appropriate tab when focused
const Titlebar = (props: TitlebarProps) => {
  let win: NarrowedWindow | null = null;
  try {
    win = getCurrentWindow();
  } catch {
    win = {
      minimize: async () => {},
      toggleMaximize: async () => {},
      close: async () => {},
    };
  }

  const windowButtons: WindowButton[] = win
    ? [
        {
          icon: "window_minimize",
          onClick: win.minimize,
        },
        {
          icon: "window_restore",
          onClick: win.toggleMaximize,
        },
        {
          icon: "close",
          onClick: win.close,
        },
      ]
    : [];

  const [draggingItem, setDraggingItem] = createSignal<string | undefined>(
    undefined,
  );

  // Overflow shadow state
  const [hasLeftOverflow, setHasLeftOverflow] = createSignal(false);
  const [hasRightOverflow, setHasRightOverflow] = createSignal(false);

  // Ref for the scrollable container
  let scrollContainer!: HTMLDivElement;

  const checkOverflow = () => {
    const { scrollLeft, scrollWidth, clientWidth } = scrollContainer;
    setHasLeftOverflow(scrollLeft > 0);
    setHasRightOverflow(scrollLeft < scrollWidth - clientWidth - 1);
  };

  onMount(() => {
    // Check overflow on mount and resize
    setTimeout(checkOverflow, 0); // Check after DOM is updated
    window.addEventListener("resize", checkOverflow);

    return () => window.removeEventListener("resize", checkOverflow);
  });

  createEffect(() => {
    const statusBarItem = statusBar.createItem({
      id: "fe.titlebar_dragging",
      alignment: "left",
      kind: "text",
    });
    statusBarItem.content = () => (
      <Show when={draggingItem()}>{`Moving tab: '${draggingItem()}'`}</Show>
    );
  });

  return (
    <div
      data-tauri-drag-region
      class="bg-theme-panel-tab-background-idle border-theme-border flex h-8
        min-h-8 items-center justify-between overflow-x-hidden border-b pl-2
        relative"
    >
      <Icon kind="fe" noDefaultStyles={true} class="size-6 pr-2" />

      {/* Left shadow overlay */}
      <div
        class={clsx(
          "absolute top-0 h-full w-8 pointer-events-none z-10",
          "bg-gradient-to-r from-theme-panel-tab-background-idle to-transparent",
          hasLeftOverflow() ? "opacity-100" : "opacity-0",
        )}
        style="left: 1.5rem; transition: opacity 0.2s ease-in-out"
      />

      {/* Right shadow overlay */}
      <div
        class={clsx(
          "absolute top-0 h-full w-8 pointer-events-none z-10",
          "bg-gradient-to-l from-theme-panel-tab-background-idle to-transparent",
          hasRightOverflow() ? "opacity-100" : "opacity-0",
        )}
        style="right: 7.5rem; transition: opacity 0.2s ease-in-out"
      />

      {/* Left-aligned content */}
      <div
        class="box-border flex h-full grow place-items-center overflow-x-auto
          no-scrollbar"
        ref={scrollContainer}
        onScroll={checkOverflow}
      >
        {/* Tabs list */}
        <DragDropProvider
          onDragStart={({ draggable }) => {
            const drag = props.workspaces.find((s) => s.uuid === draggable.id);
            if (!drag) return;
            setDraggingItem(drag.title);
          }}
          onDragEnd={({ draggable, droppable }) => {
            setDraggingItem(undefined);

            if (!droppable) return;

            const drag_idx = props.workspaces.findIndex(
              (s) => s.uuid === draggable.id,
            );
            const drop_idx = props.workspaces.findIndex(
              (s) => s.uuid === droppable.id,
            );
            if (drag_idx === -1 || drop_idx === -1) return;
            return props.onReorder(drag_idx, drop_idx);
          }}
          collisionDetector={closestCenter}
        >
          <DragDropSensors />
          <div class="flex h-full items-center pl-2">
            <For each={props.workspaces}>
              {(workspace, index) => (
                <WorkspaceTabHandle
                  uuid={workspace.uuid}
                  name={workspace.title}
                  index={index()}
                  activeIndex={props.activeIndex}
                  onClick={() => props.onActiveIndexChange(index())}
                  onCloseClick={() => {
                    props.onCloseClick(index());
                    checkOverflow();
                  }}
                />
              )}
            </For>
          </div>
          <DragOverlay>
            <div class="h-8">
              <WorkspaceTabHandleImpl
                name={draggingItem() as string}
                // kind={null}
                active={true}
                hovering={false}
                onClick={() => {}}
                onCloseClick={() => {}}
              />
            </div>
          </DragOverlay>
        </DragDropProvider>

        <div
          class="hover:bg-theme-icon-base-fill active:bg-theme-icon-active-fill
            ml-2 cursor-pointer rounded-sm p-1"
          onClick={() => {
            props.onNewClick();
            checkOverflow();
          }}
        >
          <Icon kind="add" class="size-4" />
        </div>
      </div>

      {/* Right-aligned content */}
      <div class="flex h-full">
        <For each={windowButtons}>
          {(button) => (
            <div
              class="hover:bg-theme-icon-base-fill
                active:bg-theme-icon-active-fill inline-flex h-full w-10
                items-center justify-center hover:cursor-pointer"
              onClick={button.onClick}
            >
              <Icon kind={button.icon} class="size-4" />
            </div>
          )}
        </For>
      </div>
    </div>
  );
};

type WindowButton = {
  icon: IconKind;
  onClick: () => void;
};

type WorkspaceTabHandleProps = {
  uuid: string;
  name: string;
  index: number;
  activeIndex: number | undefined;
  onClick: () => void;
  onCloseClick: () => void;
};

const WorkspaceTabHandle = (props: WorkspaceTabHandleProps) => {
  // @FIXME: better ids, uuid?
  const draggable = createDraggable(props.uuid);
  const droppable = createDroppable(props.uuid);
  // this is just to tell typescript we are using this even
  // if it doesn't know it
  /* eslint-disable */
  true && draggable;
  true && droppable;
  /* eslint-enable */

  return (
    <div //
      use:draggable
      use:droppable
      data-index={props.index}
      class="h-full"
    >
      <WorkspaceTabHandleImpl
        name={props.name}
        active={props.index === props.activeIndex}
        hovering={droppable.isActiveDroppable}
        onClick={props.onClick}
        onCloseClick={props.onCloseClick}
      />
    </div>
  );
};

type WorkspaceTabHandleImplProps = {
  name: string;
  active: boolean;
  hovering: boolean;
  onClick: () => void | null;
  onCloseClick: () => void | null;
};

const WorkspaceTabHandleImpl = (props: WorkspaceTabHandleImplProps) => {
  return (
    <div // Tab
      class={clsx(
        `hover:bg-theme-panel-tab-background-active group inline-flex h-full
        items-center gap-2 px-2 text-sm whitespace-nowrap`,
        {
          "bg-theme-panel-tab-background-idle":
            !props.active && !props.hovering,
          "bg-theme-panel-tab-background-active": props.active,
          "bg-theme-panel-tab-background-drop-target": props.hovering,
        },
      )}
      onMouseDown={(event) => {
        switch (event.button) {
          case 0:
            event.stopPropagation();
            props?.onClick();
            break;

          case 1:
            event.stopPropagation();
            props?.onCloseClick();
            break;
        }
      }}
    >
      {props.name}

      <div // Close icon
        class={clsx(
          `hover:bg-theme-icon-base-fill active:bg-theme-icon-active-fill
          cursor-pointer rounded-xl p-1 opacity-0 group-hover:opacity-100`,
          props.active && "opacity-100",
        )}
        onClick={(event) => {
          event.stopPropagation();
          props?.onCloseClick();
        }}
      >
        <Icon kind="close" class="size-3" />
      </div>
    </div>
  );
};

export default Titlebar;
