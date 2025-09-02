import { Effect, Option, Order, pipe } from "effect";
import { createMemo, createSignal, For, onCleanup, onMount } from "solid-js";
import { css } from "solid-styled-components";
import { MapOption } from "solid-effect";
import { makePersisted } from "@solid-primitives/storage";

import { DragLocationHistory } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";
import { draggable } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";

import { cn } from "~/lib/cn";
import { storeUpdate } from "~/lib/SignalObject";

import Dialog from "~/ui/components/Dialog";
import Button from "~/ui/components/Button";

import * as Panel from "./Panel";
import PropertyEditor from "./PropertyEditor";

const getPanel = (tree: Panel.Tree, id: Panel.ID) =>
  Panel.getNode(tree, { id }).pipe(Effect.runSync);

export type RenderPanelPillProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  selectedId: () => Option.Option<Panel.ID>;
  selectPanel: (id: Panel.ID) => void;

  panelId: () => Panel.ID;
  indent: number;
};

export const RenderPanelPill = (props: RenderPanelPillProps) => {
  const panel = () => getPanel(props.tree, props.panelId());

  return (
    <>
      <div class="flex flex-row my-0.5">
        <div
          style={{
            "padding-left": `${props.indent * 2}rem`,
          }}
        />

        <Button
          color="orange"
          highlighted={Option.getOrNull(props.selectedId()) === props.panelId()}
          onClick={(event) => {
            event.stopPropagation();
            props.selectPanel(props.panelId());
          }}
        >
          {panel().dbgName}
        </Button>
      </div>

      <div class="flex flex-col">
        <For each={panel().children}>
          {(childId) => {
            return (
              <RenderPanelPill
                {...props}
                panelId={() => childId}
                indent={props.indent + 1}
              />
            );
          }}
        </For>
      </div>
    </>
  );
};

type PanelInspectorProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  panelId: () => Panel.ID;
  selectPanel: (id: Panel.ID) => void;
  deselectPanel: () => void;
};

const PanelInspector = (props: PanelInspectorProps) => {
  const panel = createMemo(() => getPanel(props.tree, props.panelId()));

  const [showConfirmDelete, setShowConfirmDelete] = createSignal(false);

  return (
    <div class="font-mono">
      <PropertyEditor name="panel-inspector" showHeader={true}>
        <PropertyEditor.String
          key="Debug name"
          value={panel().dbgName}
          onUpdate={(dbgName) => {
            Panel.updateNode(props.setTree, {
              id: panel().id,
              props: { dbgName },
            }).pipe(Effect.runSync);
          }}
        />

        <PropertyEditor.Button
          key="Delete panel?"
          onClick={Option.getOrUndefined(
            Option.map(panel().parent, () => () => setShowConfirmDelete(true)),
          )}
        >
          Delete
          <Dialog
            open={showConfirmDelete()}
            onOpenChange={setShowConfirmDelete}
          >
            <Dialog.Content noCloseButton>
              <Dialog.Header>
                <Dialog.Title>
                  Are you sure you want to delete this panel?
                </Dialog.Title>
              </Dialog.Header>
              <Dialog.Footer>
                <Button
                  color="green"
                  onClick={() => setShowConfirmDelete(false)}
                >
                  cancel
                </Button>
                <Button
                  color="red"
                  noOnClickToOnMouseDown
                  onClick={() =>
                    Effect.gen(function* () {
                      const id = panel().id;
                      const parentId = yield* panel().parent;
                      props.deselectPanel();
                      yield* Panel.deleteNode(props.setTree, { id });
                      props.selectPanel(parentId);
                    }).pipe(Effect.runSync)
                  }
                >
                  delete
                </Button>
              </Dialog.Footer>
            </Dialog.Content>
          </Dialog>
        </PropertyEditor.Button>

        <PropertyEditor.Button
          key="Parent"
          onClick={Option.map(
            panel().parent,
            (id) => () => props.selectPanel(id),
          ).pipe(Option.getOrUndefined)}
        >
          {Option.map(panel().parent, (id) =>
            Panel.getNode(props.tree, { id }).pipe(
              Effect.map((panel) => panel.dbgName),
              Effect.runSync,
            ),
          ).pipe(Option.getOrElse(() => "null"))}
        </PropertyEditor.Button>

        <PropertyEditor.Enum
          key="Layout"
          value={panel().layout}
          options={["vertical", "horizontal"]}
          onChange={(value) => {
            Panel.updateNode(props.setTree, {
              id: panel().id,
              props: {
                layout: value as Panel.Layout,
              },
            }).pipe(Effect.runSync);
          }}
        />

        <PropertyEditor.Array
          key="Children"
          items={Array.from(panel().children).map((id) =>
            Panel.getNode(props.tree, { id }).pipe(
              Effect.map((panel) => panel),
              Effect.runSync,
            ),
          )}
          render={(item) => (
            <Button
              size="small"
              color="aqua"
              class="h-full pt-1"
              onClick={() => props.selectPanel(item.id)}
            >
              {item.dbgName}
            </Button>
          )}
          last={() => (
            <PropertyEditor.AddString
              placeholder="new child name"
              defaultValue="new child"
              onSubmit={(name) => {
                Effect.gen(function* () {
                  const newChildId = yield* Panel.createNode(props.setTree, {
                    dbgName: name,
                  });
                  yield* Panel.addChild(props.setTree, {
                    parentId: panel().id,
                    newChildId,
                  });
                }).pipe(Effect.runSync);
              }}
            />
          )}
        />

        <PropertyEditor.Button
          key="redistribute children?"
          onClick={() =>
            Panel.redistributeChildren(props.setTree, { id: panel().id }).pipe(
              Effect.runSync,
            )
          }
        >
          redistribute
        </PropertyEditor.Button>

        <PropertyEditor.Button
          key="balance children?"
          onClick={() =>
            Panel.uniformChildren(props.setTree, { id: panel().id }).pipe(
              Effect.runSync,
            )
          }
        >
          balance
        </PropertyEditor.Button>

        <PropertyEditor.String
          key="% of parent"
          value={(panel().percentOfParent * 100).toFixed(2)}
          // format={(str) => str + "%"}
          onUpdate={(update) => {
            const num = Order.clamp(Order.number)({
              minimum: 0,
              maximum: 100,
            })(parseFloat(update));

            Effect.gen(function* () {
              yield* Panel.updateNode(props.setTree, {
                id: panel().id,
                props: {
                  percentOfParent: Panel.Percent(num / 100),
                },
              });

              const parent = yield* panel().parent;
              yield* Panel.redistributeChildren(props.setTree, {
                id: parent,
                exclude: [panel().id],
              });
            }).pipe(Effect.runSync);
          }}
        />

        <PropertyEditor.String
          key="Children % valid"
          value={pipe(
            Effect.if(panel().children.length !== 0, {
              onFalse: () => Effect.succeed("No children"),
              onTrue: () =>
                Panel.validateChildrenSizes(props.tree, {
                  id: panel().id,
                }).pipe(
                  Effect.flatMap(({ ok, difference }) =>
                    Effect.if(ok, {
                      onTrue: () => Effect.succeed("Valid"),
                      onFalse: () =>
                        Effect.succeed(
                          `Invalid (${(difference * 100).toFixed(2)}%)`,
                        ),
                    }),
                  ),
                ),
            }),
            Effect.runSync,
          )}
        />

        <PropertyEditor.Array
          key="Tabs"
          items={panel().tabs}
          render={(tab) => tab.title}
          last={() => (
            <PropertyEditor.AddString
              placeholder="new tab name"
              defaultValue="new tab"
              onSubmit={(title) => {
                storeUpdate(props.setTree, (tree) =>
                  Effect.gen(function* () {
                    const node = yield* Panel.getNode(tree, { id: panel().id });
                    node.tabs.push({ title });
                  }).pipe(Effect.runSync),
                );
              }}
            />
          )}
        />
      </PropertyEditor>
    </div>
  );
};

export type InspectorProps = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;

  selectedId: () => Option.Option<Panel.ID>;
  setSelectedId: (id: Option.Option<Panel.ID>) => void;
};

const Inspector = (props: InspectorProps) => {
  let componentRef!: HTMLDivElement;
  let sidePanelRef!: HTMLDivElement;
  let dividerRef!: HTMLDivElement;

  const [startingSize, setStartingSize] = makePersisted(createSignal(400), {
    storage: sessionStorage,
    name: "panel-inspector-size",
  });

  onMount(() => {
    const getResizeSize = (location: DragLocationHistory): number => {
      const delta =
        location.current.input.clientY - location.initial.input.clientY;

      const margin = componentRef.clientHeight * 0.1;
      return Order.clamp(Order.number)({
        minimum: margin,
        maximum: componentRef.clientHeight - margin,
      })(startingSize() - delta);
    };

    const dragCleanup = draggable({
      element: dividerRef,

      onGenerateDragPreview: ({ nativeSetDragImage }) => {
        disableNativeDragPreview({ nativeSetDragImage });
        preventUnhandled.start();
      },

      onDrag: ({ location }) => {
        const resizeSize = getResizeSize(location);

        sidePanelRef.style.setProperty(
          "--local-resizing-size",
          `${resizeSize}`,
        );
      },

      onDrop: ({ location }) => {
        preventUnhandled.stop();

        const resizeSize = getResizeSize(location);
        setStartingSize(resizeSize);
        sidePanelRef.style.removeProperty("--local-resizing-size");
      },
    });

    onCleanup(() => {
      dragCleanup();
    });
  });

  return (
    <div ref={componentRef} class="flex flex-col w-auto h-full">
      <div
        class="p-2 font-mono grow overflow-auto min-h-0"
        onClick={() => props.setSelectedId(Option.none())}
      >
        <RenderPanelPill
          tree={props.tree}
          setTree={props.setTree}
          selectedId={props.selectedId}
          selectPanel={(id) => props.setSelectedId(Option.some(id))}
          panelId={() => props.tree.root}
          indent={0}
        />
      </div>

      <div
        ref={dividerRef}
        class={cn(
          "h-[1px] bg-theme-border cursor-ns-resize relative",
          css`
            &::before {
              content: "";
              top: 0;
              position: absolute;
              width: 100%;
              height: 1rem;
              left: -0.5rem;
            }
          `,
        )}
      />

      <div
        ref={sidePanelRef}
        class="flex flex-col p-0.5 gap-2 overflow-auto"
        style={{
          "--local-starting-size": startingSize(),
          height: `calc(var(--local-resizing-size, var(--local-starting-size)) * 1px)`,
        }}
      >
        <div class="ml-2 mt-2 flex gap-1">
          {/*<Button
            color="pink"
            onClick={() => {
              for (const [id, panel] of Object.entries(props.tree.nodes)) {
                console.log("id:", id, ",", "dbgName:", panel.dbgName);
              }
            }}
          >
            Print all panels
          </Button>*/}

          {/*<Button color="pink" onClick={() => setShowDialog(true)}>
            show dialog
          </Button>*/}

          {/*<Dialog open={showDialog()} onOpenChange={setShowDialog}>*/}
          <Dialog>
            <Dialog.Trigger as={Button} color="pink">
              show dialog
            </Dialog.Trigger>
            <Dialog.Content>
              <Dialog.Header>
                <Dialog.Title>Title!</Dialog.Title>
              </Dialog.Header>
              <Dialog.Description>Description!</Dialog.Description>
              yo!
              <Dialog.Footer>Footer!</Dialog.Footer>
            </Dialog.Content>
          </Dialog>

          {/*<Dialog open={showDialog()} onClose={() => setShowPortal(false)}>
            yo!
          </Dialog>*/}

          {/*<Button color="red">button</Button>
          <Button color="pink" disabled>
            disabled
          </Button>
          <Button color="red" size="small">
            small
          </Button>
          <Button color="blue" variant="outline">
            outline
          </Button>
          <Button color="yellow" variant="ghost">
            ghost
          </Button>
          <Button
            variant="link"
            as="a"
            href="https://example.com"
            target="_blank"
          >
            Link
          </Button>*/}
        </div>

        {/*<Show when={showPortal()}>
          <Portal mount={themeContext.rootElement()}>
            <div
              class="fixed top-0 left-0 w-full h-full bg-theme-background/60"
              onClick={() => setShowPortal(false)}
            />
            <div class="fixed top-[50%] left-[50%] transform-[translate(-50%, -50%)] bg-theme-background border p-2 rounded-md shadow">
              yo!
            </div>
          </Portal>
        </Show>*/}

        <MapOption on={props.selectedId()}>
          {(selectedId) => (
            <PanelInspector
              tree={props.tree}
              setTree={props.setTree}
              panelId={selectedId}
              selectPanel={(id) => props.setSelectedId(Option.some(id))}
              deselectPanel={() => props.setSelectedId(Option.none())}
            />
          )}
        </MapOption>

        {/*<ParentComponent>
          <MyTokenA> 1 A 1st</MyTokenA>
          <MyTokenB> 1 B 2nd </MyTokenB>
          <MyTokenA> 2 A 3rd </MyTokenA>
        </ParentComponent>*/}
      </div>
    </div>
  );
};

export default Inspector;

// import {
//   createTokenizer,
//   createToken,
//   resolveTokens,
// } from "@solid-primitives/jsx-tokenizer";
// import { ColorKind } from "~/Theme";
// import { Icon } from "~/assets/icons";
// import { Button } from "~/ui/components/Button";

// type TokenProps = ParentProps<{ type: "A" | "B"; color?: ColorKind }>;
// const Tokenizer = createTokenizer<TokenProps>({
//   name: "Example Tokenizer",
// });

// type MyTokenAProps = ParentProps<{}>;
// const MyTokenA = createToken<MyTokenAProps, TokenProps>(Tokenizer, (props) => ({
//   type: "A",
//   ...props,
// }));
// type MyTokenBProps = ParentProps<{ color?: ColorKind }>;
// const MyTokenB = createToken<MyTokenBProps, TokenProps>(Tokenizer, (props) => ({
//   type: "B",
//   ...props,
// }));

// function ParentComponent(props: ParentProps<{}>) {
//   const tokens = resolveTokens<TokenProps>(Tokenizer, () => props.children);

//   const allA = tokens().filter((token) => token.data.type === "A");
//   const allB = tokens().filter((token) => token.data.type === "B");

//   return (
//     <ul>
//       {/*<For each={tokens()}>{(token) => <li>{token.data.type}</li>}</For>*/}
//       <For each={allA}>{(token) => <li>{token.data.children}</li>}</For>
//       <For each={allB}>{(token) => <li>{token.data.children}</li>}</For>
//     </ul>
//   );
// }

// // <ParentComponent>
// //   <MyTokenA />
// //   <MyTokenB />
// // </ParentComponent>;

// // function Tabs<T>(props: {
// //   children: (Tab: Component<{ value: T }>) => JSX.Element;
// //   active: T;
// // }) {
// //   const Tab = createToken((props: { value: T }) => props.value);
// //   // resolveTokens will look for tokens created by Tab component
// //   const tokens = resolveTokens(Tab, () => props.children(Tab));
// //   return (
// //     <ul>
// //       <For each={tokens()}>
// //         {(token) => (
// //           <li classList={{ active: token.data === props.active }}>
// //             {token.data as any}
// //           </li>
// //         )}
// //       </For>
// //     </ul>
// //   );
// // }

// // // usage
// // <Tabs active="tab1">
// //   {(Tab) => (
// //     <>
// //       <Tab value="tab1" />
// //       <Tab value="tab2" />
// //     </>
// //   )}
// // </Tabs>;
