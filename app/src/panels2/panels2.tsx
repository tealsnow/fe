import { createEvent } from "solid-events";
import { createSignal, For, Show } from "solid-js";
import { createStore } from "solid-js/store";

import { Console, Effect, Match, Option, pipe } from "effect";

import { cn } from "~/lib/cn";
import { storeObjectProduceFromStore } from "~/lib/SignalObject";
import { NotificationType, notify } from "~/notifications";
import Lozenge from "~/ui/components/Lozenge";

import PanelsExplorer from "./explorer";
import {
  NullPanelNode,
  PanelEvent,
  PanelEventEmitter,
  PanelId,
  PanelLayout,
  PanelNode,
  panels,
  PanelTreeData,
  PanelTreeStore,
  Percent,
} from "./panel";

export type RenderPanelProps = {
  treeStore: PanelTreeStore;
  emitEvent: PanelEventEmitter;

  parentLayout: PanelLayout;
  panelId: PanelId;
};

export const RenderPanel = (props: RenderPanelProps) => {
  const panel = () => props.treeStore.value[props.panelId] ?? NullPanelNode;

  return (
    <div
      class="flex flex-col w-full h-full border-theme-colors-purple-border border"
      style={
        props.parentLayout === "vertical"
          ? {
              width: "100%",
              height: panel().percentOfParent * 100 + "%",
            }
          : {
              width: panel().percentOfParent * 100 + "%",
              height: "100%",
            }
      }
    >
      <div class="flex flex-row w-full h-fit p-0.5 gap-1 items-center border-b border-theme-colors-purple-border">
        <Lozenge
          color="orange"
          class="min-w-10"
          interactive
          onClick={() =>
            props.emitEvent(PanelEvent.select({ id: props.panelId }))
          }
        >
          {panel().dbgName}
        </Lozenge>
        {(panel().percentOfParent * 100).toFixed(2)}% Children %:
        {panels
          .validateChildrenSizes(props.treeStore.value, props.panelId)
          .pipe(
            Effect.map(({ ok, difference }) => (
              <>
                {ok ? (
                  <div class="text-green-500">OK</div>
                ) : (
                  <div class="text-red-500">
                    Error: difference: {difference}
                  </div>
                )}
              </>
            )),
            Effect.runSync,
          )}
      </div>

      <div
        class={cn(
          "flex w-full h-full gap-1 p-1",
          panel().layout === "vertical" && "flex-col",
          panel().layout === "horizontal" && "flex-row",
        )}
      >
        <For each={panel().children}>
          {(panelId) => {
            return (
              <RenderPanel
                treeStore={props.treeStore}
                emitEvent={props.emitEvent}
                parentLayout={panel().layout}
                panelId={panelId}
              />
            );
          }}
        </For>
      </div>
    </div>
  );
};

export type RenderPanelsProps = {
  treeStore: PanelTreeStore;

  root: PanelId;
  selectedId: PanelId | null;

  emitEvent: PanelEventEmitter;
};

export const RenderPanels = (props: RenderPanelsProps) => {
  return (
    <RenderPanel
      treeStore={props.treeStore}
      emitEvent={props.emitEvent}
      parentLayout="vertical"
      panelId={props.root}
    />
  );
};

type NotifyLogParams = {
  type?: NotificationType;
  notification: string;
  log: Option.Option<string>;
};

// @TODO: Factor into own file
export const notifyLog = (
  params: NotifyLogParams,
): Effect.Effect<void, never> => {
  const type = params.type ?? "default";
  const notification = params.notification;
  const log = params.log.pipe(Option.getOrElse(() => notification));

  notify(notification, { type });

  switch (type) {
    case "default":
    /* fallthrough */
    case "success":
      console.log(log);
      break;
    case "loading":
      console.debug("loading:", log);
      break;
    case "error":
      console.error(log);
      break;
    case "warning":
      console.warn(log);
      break;
    case "info":
      console.info(log);
      break;
  }

  return Effect.void;
};

const Panels2 = () => {
  const treeStore = storeObjectProduceFromStore(createStore<PanelTreeData>());
  const root = panels.createRootPanelNode(treeStore);

  const [selectedId, setSelectedId] = createSignal<PanelId | null>(root);

  const [showExplorer, setShowExplorer] = createSignal(true);

  const [onEvent, emitEvent] = createEvent<PanelEvent>();
  onEvent((event) => {
    Match.value(event).pipe(
      Match.tag("addChild", (event) =>
        panels.addChild(treeStore, event.id, event.childId).pipe(
          Effect.matchEffect({
            onFailure: (error) => {
              return Effect.void;
            },
            onSuccess: (childId) => {
              return Effect.void;
            },
          }),
          Effect.runSync,
        ),
      ),
      Match.tag("select", (event) => {
        // @BUG: ? I don't get it:
        //   without this going between null and PanelId updates the Inspect
        //   but going from PanelId to PanelId doesn't
        //   even this fix just puts it to null first before any change...
        setSelectedId(null);

        setSelectedId((id) => (id === event.id ? null : event.id));
      }),
      Match.tag("delete", (event) =>
        panels.deletePanel(treeStore, event.id).pipe(
          Effect.matchEffect({
            onFailure: (error) =>
              Match.value(error).pipe(
                Match.withReturnType<NotifyLogParams>(),
                Match.tag("CannotDeleteRootPanelError", () => ({
                  type: "error",
                  notification: "Cannot delete root panel",
                  log: Option.none(),
                })),
                Match.tag("PanelDoesNotExistError", ({ id, parentList }) => ({
                  type: "error",
                  notification: `Panel width id: '${id}' does not exist`,
                  log: Option.some(
                    `Panel width id: '${id}' does not exist; ` +
                      `parent chain: ${JSON.stringify(parentList)}`,
                  ),
                })),
                Match.exhaustive,
                notifyLog,
                Effect.succeed,
                Effect.runSync,
              ),
            onSuccess: () => {
              if (event.id === selectedId()) setSelectedId(null);
              return Effect.void;
            },
          }),
          Effect.runSync,
        ),
      ),
      Match.tag("update", (event) =>
        panels.update(treeStore, event.id, event.props).pipe(Effect.runSync),
      ),
      Match.exhaustive,
    );
  });

  Effect.gen(function* () {
    const child_a = panels.newPanelNode(treeStore, {
      dbgName: "a",
      layout: "vertical",
    });
    const child_b = panels.newPanelNode(treeStore, { dbgName: "b" });
    const child_c = panels.newPanelNode(treeStore, {
      dbgName: "c",
      percentOfParent: Percent(0.5),
    });
    const child_d = panels.newPanelNode(treeStore, {
      dbgName: "d",
      percentOfParent: Percent(1),
    });

    yield* panels.addChild(treeStore, root, child_a);
    yield* panels.addChild(treeStore, root, child_b);

    yield* panels.addChild(treeStore, child_a, child_c);
    yield* panels.addChild(treeStore, child_a, child_d);
  }).pipe(
    Effect.catchTag("PanelDoesNotExistError", ({ id }) =>
      Console.error(
        `failed to init, got panel does not exist error: id: '${id}'`,
      ),
    ),
    Effect.runSync,
  );

  return (
    <div class="flex flex-col w-full h-full">
      <div class="flex flex-row h-10 border-b border-theme-border items-center px-2">
        <For
          each={[
            {
              get: showExplorer,
              set: setShowExplorer,
              lbl: "show explorer",
            },
          ]}
        >
          {({ get, set, lbl }) => (
            <label class="flex flex-row gap-1">
              <input
                type="checkbox"
                checked={get()}
                id={lbl}
                class="form-checkbox border-1 border-theme-colors-purple-border
                  bg-theme-colors-purple-background outline-0
                  checked:bg-theme-colors-purple-base ring-offset-0 ring-0"
                onChange={({ target: { checked } }) => {
                  set(checked);
                }}
              />
              {lbl}
            </label>
          )}
        </For>
      </div>

      <div class="flex flex-row w-full h-full">
        <div
          class={cn(
            "h-full border-r border-theme-border p-0.5",
            showExplorer() ? "w-[50%]" : "w-full",
          )}
        >
          <RenderPanels
            treeStore={treeStore}
            root={root}
            selectedId={selectedId()}
            emitEvent={emitEvent}
          />
        </div>

        <Show when={showExplorer()}>
          <div class="w-[50%]">
            <PanelsExplorer
              treeStore={treeStore}
              root={root}
              selectedId={selectedId()}
              emitEvent={emitEvent}
            />
          </div>
        </Show>
      </div>
    </div>
  );
};

export default Panels2;
