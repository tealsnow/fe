import { Effect, Option, Order } from "effect";
import { createSignal, For, onCleanup, onMount, Switch } from "solid-js";
import { css } from "solid-styled-components";
import { MapOption } from "solid-effect";
import { makePersisted } from "@solid-primitives/storage";

import { DragLocationHistory } from "@atlaskit/pragmatic-drag-and-drop/dist/types/internal-types";
import { draggable } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { disableNativeDragPreview } from "@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview";
import { preventUnhandled } from "@atlaskit/pragmatic-drag-and-drop/prevent-unhandled";

import { cn } from "~/lib/cn";
import { MatchTag } from "~/lib/MatchTag";

import Dialog from "~/ui/components/Dialog";
import Button from "~/ui/components/Button";
import PropertyEditor from "~/ui/components/PropertyEditor";

import * as Panel from "./Panel";
import { usePanelContext } from "./PanelContext";

const getPanel = (tree: Panel.Tree, id: Panel.ID) =>
  Panel.Node.getOrError(tree, { id }).pipe(Effect.runSync);

export type RenderPanelPillProps = {
  panelId: () => Panel.ID;
  indent: number;
};

export const RenderPanelPill = (props: RenderPanelPillProps) => {
  const { tree, dbg } = usePanelContext();

  const panel = () => getPanel(tree, props.panelId());

  const selected = () =>
    Option.getOrElse(
      // false positive
      // eslint-disable-next-line solid/reactivity
      Option.map(dbg.selectedId(), (id) => id === props.panelId()),
      () => false,
    );

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
          size="small"
          highlighted={selected()}
          onClick={(event) => {
            event.stopPropagation();
            dbg.setSelectedId(Option.some(props.panelId()));
          }}
        >
          {panel().id.uuid}
        </Button>
      </div>

      <MapOption on={Panel.Node.$as("parent")(panel())}>
        {(parent) => {
          return (
            <div class="flex flex-col">
              <For each={parent().layout.children}>
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
          );
        }}
      </MapOption>
    </>
  );
};

type PanelInspectorProps = {
  panelId: () => Panel.ID;
};

const PanelInspector = (props: PanelInspectorProps) => {
  const { tree, setTree, dbg } = usePanelContext();

  const panel = () => getPanel(tree, props.panelId());

  const [showConfirmDelete, setShowConfirmDelete] = createSignal(false);

  return (
    <div class="font-mono">
      <PropertyEditor name="panel-inspector" showHeader={true}>
        <PropertyEditor.String
          key="id"
          value={panel().id.uuid}
          valueClass="text-xs text-center"
        />

        <PropertyEditor.Button
          key="Parent"
          onClick={Option.map(
            panel().parent,
            (id) => () => dbg.setSelectedId(Option.some(id)),
          ).pipe(Option.getOrUndefined)}
        >
          <span class="text-xs">
            {Option.map(panel().parent, (id) =>
              Panel.Node.Parent.getOrError(tree, { parentId: id }).pipe(
                Effect.map((panel) => panel.id.uuid),
                Effect.runSync,
              ),
            ).pipe(Option.getOrElse(() => "null"))}
          </span>
        </PropertyEditor.Button>

        <PropertyEditor.String
          key="% of parent"
          value={(panel().percentOfParent * 100).toFixed(2)}
          format={(str) => str + "%"}
          onUpdate={(update) => {
            const num = Order.clamp(Order.number)({
              minimum: 0,
              maximum: 100,
            })(parseFloat(update));
            const percent = Panel.Percent(num / 100);

            Panel.Node.setPercentOfParent(setTree, {
              id: panel().id,
              percent,
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
                    // false positive
                    // eslint-disable-next-line solid/reactivity
                    Effect.gen(function* () {
                      const id = panel().id;
                      const parentId = yield* panel().parent;
                      dbg.setSelectedId(Option.none());
                      yield* Panel.Node.destroy(setTree, { id });
                      dbg.setSelectedId(Option.some(parentId));
                    }).pipe(
                      // Effect.catchAllDefect((defect) => {
                      //   console.error(defect);
                      //   return Effect.succeed(void {});
                      // }),
                      // Effect.catchAll((err) => {
                      //   console.error(err);
                      //   return Effect.succeed(void {});
                      // }),
                      Effect.runSync,
                    )
                  }
                >
                  delete
                </Button>
              </Dialog.Footer>
            </Dialog.Content>
          </Dialog>
        </PropertyEditor.Button>

        <Switch>
          <MatchTag on={panel()} tag="leaf">
            {(leaf) => {
              return (
                <PropertyEditor.String
                  key="Title"
                  value={leaf().title}
                  onUpdate={(title) => {
                    Panel.Node.Leaf.update(setTree, {
                      id: leaf().id,
                      props: { title },
                    }).pipe(Effect.runSync);
                  }}
                />
              );
            }}
          </MatchTag>
          <MatchTag on={panel()} tag="parent">
            {(parent) => {
              return (
                <>
                  <Switch>
                    <MatchTag on={parent().layout} tag="split">
                      {(split) => (
                        <PropertyEditor.Enum
                          key="Split direction"
                          value={split().direction}
                          options={["vertical", "horizontal"]}
                          onChange={(value) => {
                            Panel.Node.Parent.update(setTree, {
                              id: parent().id,
                              props: {
                                layout: {
                                  _tag: "split",
                                  direction:
                                    value as Panel.Layout.SplitDirection,
                                  children: split().children,
                                },
                              },
                            }).pipe(Effect.runSync);
                          }}
                        />
                      )}
                    </MatchTag>
                  </Switch>

                  <PropertyEditor.Array
                    key="Children"
                    items={Array.from(parent().layout.children).map((id) =>
                      Panel.Node.get(tree, { id }).pipe(
                        Effect.map((panel) => panel),
                        Effect.runSync,
                      ),
                    )}
                    previewCount={3}
                    preview={(item) => (
                      <Button
                        as="span"
                        size="small"
                        color="aqua"
                        class="h-full pt-1 text-xs/tight w-20 overflow-hidden whitespace-nowrap text-ellipsis text-left text-nowrap"
                        onClick={() => dbg.setSelectedId(Option.some(item.id))}
                      >
                        {item.id.uuid}
                      </Button>
                    )}
                    render={(item) => (
                      <Button
                        size="small"
                        color="aqua"
                        class="h-full pt-1 text-xs/tight"
                        onClick={() => dbg.setSelectedId(Option.some(item.id))}
                      >
                        {item.id.uuid}
                      </Button>
                    )}
                    // last={() => (
                    //   <PropertyEditor.AddString
                    //     placeholder="new child name"
                    //     defaultValue="new child"
                    //     onSubmit={(name) => {
                    //       Effect.gen(function* () {
                    //         const newChildId = yield* Panel.createNode(
                    //           props.setTree,
                    //           {
                    //             dbgName: name,
                    //           },
                    //         );
                    //         yield* Panel.addChild(props.setTree, {
                    //           parentId: panel().id,
                    //           newChildId,
                    //         });
                    //       }).pipe(Effect.runSync);
                    //     }}
                    //   />
                    // )}
                  />

                  <PropertyEditor.Button
                    key="redistribute children?"
                    onClick={() =>
                      Panel.Node.Parent.redistributeChildren(setTree, {
                        parentId: parent().id,
                      }).pipe(Effect.runSync)
                    }
                  >
                    redistribute
                  </PropertyEditor.Button>

                  {/*<PropertyEditor.Button
                    key="balance children?"
                    onClick={() =>
                      Panel.Node.Parent.uniformChildren(props.setTree, { id: panel().id }).pipe(
                        Effect.runSync,
                      )
                    }
                  >
                    balance
                  </PropertyEditor.Button>*/}

                  {/*<PropertyEditor.String
                    key="Children % valid"
                    value={pipe(
                      Effect.if(parent().children.length !== 0, {
                        onFalse: () => Effect.succeed("No children"),
                        onTrue: () =>
                          Panel.Node.Parent.validateChildrenSizes(props.tree, {
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
                  />*/}
                </>
              );
            }}
          </MatchTag>
        </Switch>
      </PropertyEditor>
    </div>
  );
};

const Inspector = () => {
  let componentRef!: HTMLDivElement;
  let sidePanelRef!: HTMLDivElement;
  let dividerRef!: HTMLDivElement;

  // false positive
  // @TODO: file issue
  // eslint-disable-next-line solid/reactivity
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

  const { tree, dbg } = usePanelContext();

  return (
    <div ref={componentRef} class="flex flex-col w-auto h-full">
      <div
        class="p-2 font-mono grow overflow-auto min-h-0"
        onClick={() => dbg.setSelectedId(Option.none())}
      >
        <RenderPanelPill panelId={() => tree.root} indent={0} />
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
              top: -0.5rem;
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

        <MapOption on={dbg.selectedId()}>
          {(selectedId) => <PanelInspector panelId={selectedId} />}
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
