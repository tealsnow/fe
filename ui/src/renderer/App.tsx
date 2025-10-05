import {
  createSignal,
  onCleanup,
  onMount,
  Component,
  For,
  VoidComponent,
  createEffect,
} from "solid-js";

import { Effect, Match, Option } from "effect";

import { Icon, icons } from "~/assets/icons";

import { cn } from "~/lib/cn";
import Integer from "~/lib/Integer";
import * as Notif from "~/lib/Notif";
import assert from "~/lib/assert";

import Command from "~/ui/components/Command";
import Noise from "~/ui/components/Noise";

import * as Theme from "~/ui/Theme";
import * as StatusBar from "~/ui/StatusBar";
import * as Window from "~/ui/Window";
import * as Panels from "~/ui/Panels";

import Dbg from "./Dbg";
import Dialog from "./ui/components/Dialog";
import Button from "./ui/components/Button";
import { DocumentEventListener } from "@solid-primitives/event-listener";

export const App: Component = () => {
  return (
    <Window.Provider>
      <AfterWindow />
    </Window.Provider>
  );
};

const AfterWindow: Component = () => {
  // @NOTE: This applies the theme globally - setting the css vars on the
  //  document globally. This is mostly just for the toasts, since they
  //  are built with normal css.
  //  If that changes to use inline styles and/or tailwind we can remove this
  //
  //  As is stands this works just fine, if and when we do a theme preview
  //  we can just use the provider, unless we want to show what toasts would
  //  look like...
  Theme.applyThemeColors(Theme.defaultTheme.colors);

  const windowCtx = Window.useContext();

  return (
    <Theme.Provider
      theme={Theme.defaultTheme}
      class="flex w-screen h-screen"
      applyRounding={!windowCtx.maximized()}
    >
      <Notif.Provider>
        <StatusBar.Provider>
          <Panels.Context.Provider>
            <Root />
          </Panels.Context.Provider>
        </StatusBar.Provider>
      </Notif.Provider>
    </Theme.Provider>
  );
};

const Root: Component = () => {
  const [showNoise, setShowNoise] = createSignal(true);

  const windowCtx = Window.useContext();
  const themeCtx = Theme.useContext();
  const statusBarCtx = StatusBar.useContext();
  const panelCtx = Panels.useContext();
  const notifCtx = Notif.useContext();

  onMount(() => {
    panelCtx.setWorkspace((workspace) =>
      Panels.Workspace({
        ...workspace,
        root: Panels.PanelNode.makeTabs({
          active: Integer(0),
          children: [
            panelCtx.createLeaf({
              title: "text editing",
              tooltip: "text editing test",
              render: () => <TextEditing />,
            }),
            panelCtx.createLeaf({
              title: "command palette",
              tooltip: "command palette test",
              render: () => <CommandPaletteTest />,
            }),
            panelCtx.createLeaf({
              title: "dbg",
              tooltip: "testing stuff",
              render: () => <Dbg setShowNoise={setShowNoise} />,
            }),
            panelCtx.createLeaf({
              title: "theme showcase",
              tooltip: "showcase all aspects of the current theme",
              render: () => <Theme.Showcase />,
            }),
          ],
        }),
        sidebars: Panels.WorkspaceSidebars({
          left: Panels.WorkspaceSidebar({
            enabled: false,
            node: Panels.PanelNode.makeTabs(),
          }),
          right: Panels.WorkspaceSidebar({
            enabled: false,
            node: Panels.PanelNode.makeTabs(),
          }),
          bottom: Panels.WorkspaceSidebar({
            enabled: false,
            node: Panels.PanelNode.makeTabs(),
          }),
        }),
      }),
    );

    const notificationPanelId = panelCtx.createLeaf({
      title: "notifications",
      tooltip: "notifications",
      render: () => (
        <div class="w-full h-full p-2 flex flex-col gap-1">
          <For each={notifCtx.notifications}>
            {(entry) => (
              <div class="border-theme-border border p-2 rounded-md">
                {entry.content}
              </div>
            )}
          </For>
        </div>
      ),
    });

    const [cleanup, _id] = statusBarCtx.addItem({
      alignment: "right",
      item: StatusBar.BarItem.iconButton({
        icon: () => <Icon icon={icons["bell"]} />,
        tooltip: () => "notifications",
        onClick: () => {
          const sidebars = panelCtx.workspace.sidebars;

          if (Panels.PanelNode.$is("Tabs")(sidebars.right.node)) {
            // right is tabs

            const notifPanelIdx = sidebars.right.node.children.findIndex(
              (child) => child.id === notificationPanelId.id,
            );
            if (notifPanelIdx !== -1) {
              // notif panel is in right
              if (
                !sidebars.right.node.active.pipe(
                  Option.map((idx) => idx === notifPanelIdx),
                  Option.getOrElse(() => false),
                )
              )
                // notif panel is not active
                panelCtx.setWorkspace("sidebars", (sidebars) =>
                  Panels.WorkspaceSidebars({
                    ...sidebars,
                    right: Panels.WorkspaceSidebar({
                      ...sidebars.right,
                      // @ts-expect-error 2345
                      node: Panels.PanelNode.Tabs({
                        ...sidebars.right.node,
                        active: Option.some(Integer(notifPanelIdx)),
                      }),
                    }),
                  }),
                );
            } else {
              // notif panel is not in right
              panelCtx.setWorkspace("sidebars", (sidebars) =>
                Panels.WorkspaceSidebars({
                  ...sidebars,
                  right: Panels.WorkspaceSidebar({
                    ...sidebars.right,
                    node: Panels.tabsAddTab({
                      // @ts-expect-error 2322
                      tabs: sidebars.right.node,
                      newLeaf: notificationPanelId,
                    }).pipe(Effect.runSync),
                  }),
                }),
              );
            }

            if (!sidebars.right.enabled)
              // notif panel is not enabled
              panelCtx.setWorkspace("sidebars", (sidebars) =>
                Panels.WorkspaceSidebars({
                  ...sidebars,
                  right: Panels.WorkspaceSidebar({
                    ...sidebars.right,
                    enabled: true,
                  }),
                }),
              );
          } else {
            console.warn("TODO: right sidebar is not tabs");
          }
        },
      }),
    });
    onCleanup(() => cleanup());
  });

  return (
    <Noise
      class={cn(
        "flex flex-col grow relative",
        !windowCtx.maximized() && [
          themeCtx.theme().windowRounding,
          "electron-corner-smoothing-[60%] border border-theme-border",
        ],
      )}
      enabled={showNoise()}
    >
      <Panels.View.Root />

      <StatusBar.StatusBar />
    </Noise>
  );
};

const CommandPaletteTest: VoidComponent = () => {
  const [open, setOpen] = createSignal(false);

  let commandRef: HTMLDivElement | undefined;

  return (
    <div class="flex p-2 items-center gap-2">
      <DocumentEventListener
        onKeypress={(e) => {
          if (e.ctrlKey && e.key === "k") setOpen(true);
        }}
      />
      <Dialog open={open()} onOpenChange={setOpen}>
        <Dialog.Trigger as={Button} class="size-fit">
          Open
        </Dialog.Trigger>
        <kbd>Ctrl-K</kbd>
        <Dialog.Content
          noCloseButton
          class="border-0 w-1/2 bg-none shadow-none max-h-1/2"
        >
          <Command
            ref={commandRef}
            label="Command Palette"
            loop
            onKeyDown={(e) => {
              if (e.target === commandRef) {
                Match.value(e.key).pipe(
                  Match.when("Escape", () => {
                    setOpen(false);
                  }),
                  // Match.when("j", () => {
                  //   console.log("down");
                  // }),
                  // Match.when("k", () => {
                  //   console.log("up");
                  // }),
                );
              } else {
                if (e.key === "Escape") {
                  commandRef?.focus();
                  e.preventDefault();
                  return;
                }
              }
            }}
          >
            <Command.Input placeholder="Type a command or search..." />
            <Command.List>
              <Command.Empty>No results found.</Command.Empty>

              <Command.Group heading="Suggestions">
                <Command.Item
                  onSelect={() => {
                    console.log("calender selected");
                  }}
                >
                  <span>Calender</span>
                </Command.Item>
                <Command.Item keywords={["face"]}>
                  <span>Search Emoji</span>
                </Command.Item>
                <Command.Item disabled>
                  <span>Launch</span>
                </Command.Item>
              </Command.Group>

              <Command.Separator />

              <Command.Group heading="Settings">
                <Command.Item>
                  <span>Profile</span>
                  <Command.Shortcut>Ctrl-P</Command.Shortcut>
                </Command.Item>
                <Command.Item>
                  <span>Mail</span>
                  <Command.Shortcut>Ctrl-B</Command.Shortcut>
                </Command.Item>
                <Command.Item>
                  <span>Open Settings</span>
                  <Command.Shortcut>Ctrl-S</Command.Shortcut>
                </Command.Item>
              </Command.Group>
            </Command.List>
          </Command>
        </Dialog.Content>
      </Dialog>
    </div>
  );
};

const TextEditing: VoidComponent = () => {
  // This is just the beginnings of what will be the modal text editing system.
  // This just shows how much code will be needed to make this all work.
  // We have to reimplement almost all text editing functionality
  // which is really a whole lot, it never seems like much until you actually
  // start doing it.
  // So far we have the bare minimum for the most basic text input
  // Just off the top of my head whats left for somewhat parity with a text
  // input:
  //  - selection - like in general
  //  - cut copy paste
  //  - ctrl movements
  //  - clicking to move caret
  //  - delete
  //  - home, end
  // Theres certainly more, but that all just for parity for a basic text input.
  // Theres still the modal editing to do.
  // My idea is to have a global manager at the top level that will manage modes
  // and the like. Intercept input and provide state for downstream inputs to
  // get access and push to. Vague, I know, but this is right here is the start
  // to that.

  // There are two methods for calculating the caret coordinates here
  // Neither are really optimized, but thats besides the point
  //
  // The canvas api solution uses a canvas context to measure the text,
  // it is generally more performance than the DOM based approach but has a few
  // drawbacks. It has no awareness of newlines or line breaking in general.
  // Thus we cannot use the DOM logic for line wrap - we'd have to implement our
  // own.
  //
  // The second approach is the DOM based one, this is less performant but goes
  // directly through the dom, and thus is multiline aware and allows us to go
  // use the DOM line breaking logic and is generally less overall work for us.
  //
  // As it stands, the DOM approach uses more code and is less performant,
  // but supports line breaking.
  //
  // The canvas approach uses less code and is more performant, but does not
  // work for multiline. We'd have to make our own solution

  let containerRef!: HTMLDivElement;
  let textAreaRef!: HTMLTextAreaElement;

  let textRef!: HTMLDivElement;

  const [enableMono, setEnableMono] = createSignal(false);

  const [text, setText] = createSignal("some existing text\nmultiline");
  // eslint-disable-next-line solid/reactivity
  const [caretIndex, setCaretIndex] = createSignal(text().length);

  const insertText = (str: string): void => {
    const offset = caretIndex();
    setText((text) => text.slice(0, offset) + str + text.slice(offset));
  };

  const [caretX, setCaretX] = createSignal(0);
  const [caretHeight, setCaretHeight] = createSignal(0);

  const [caretX2, setCaretX2] = createSignal(0);
  const [caretY2, setCaretY2] = createSignal(0);
  const [caretHeight2, setCaretHeight2] = createSignal(0);

  createEffect(() => {
    console.group("canvas api caret calc - setup");
    const start = performance.now();
    performance.mark("canvas api caret calc - setup");

    enableMono(); // track font

    const textComputedStyle = getComputedStyle(textRef);
    const font = textComputedStyle.font;
    console.log("font:", font);

    const containerComputedStyle = getComputedStyle(containerRef);
    const leftPadding = parseFloat(containerComputedStyle.paddingLeft);

    const canvas = document.createElement("canvas");
    const context = canvas.getContext("2d")!;
    context.font = font;

    setCaretHeight(parseFloat(textComputedStyle.lineHeight));

    createEffect(() => {
      console.group("canvas api caret calc");
      const start = performance.now();

      const measure = context.measureText(text().slice(0, caretIndex()));

      const x = measure.width + leftPadding;
      console.log("x:", x);
      setCaretX(x);

      const end = performance.now();
      console.timeStamp(`time: ${end - start}ms`);
      console.groupEnd();
    });

    const end = performance.now();
    console.timeStamp(`time: ${end - start}ms`);
    console.groupEnd();
  });

  const mapIndexToNode = (
    index: number,
  ): { node: Node; localIndex: number } | null => {
    let cumulativeOffset = 0;

    const walker = document.createTreeWalker(
      textRef,
      NodeFilter.SHOW_TEXT,
      null,
    );

    let currentNode: Node | null;
    for (; (currentNode = walker.nextNode()); currentNode != null) {
      assert(currentNode.nodeType === Node.TEXT_NODE);

      const nodeTextLength = currentNode.nodeValue?.length ?? 0;

      if (cumulativeOffset + nodeTextLength >= index) {
        const localIndex = index - cumulativeOffset;
        return { node: currentNode, localIndex };
      }

      cumulativeOffset += nodeTextLength;
    }

    if (cumulativeOffset > 0) {
      const node = currentNode || walker.lastChild();
      if (!node) return null;
      return {
        node,
        localIndex: node.nodeValue?.length ?? 0,
      };
    }

    return null;
  };

  createEffect(() => {
    console.group("document range caret calc - setup");
    const start = performance.now();

    enableMono(); // track font

    const containerComputedStyle = getComputedStyle(containerRef);
    const paddingLeft = parseFloat(containerComputedStyle.paddingLeft);
    const paddingTop = parseFloat(containerComputedStyle.paddingTop);

    const range = document.createRange();

    createEffect(() => {
      console.group("document range caret calc");
      const start = performance.now();

      try {
        const nodeMapping = mapIndexToNode(caretIndex());

        if (!nodeMapping) {
          console.warn("empty line?");
          return;
        }

        const { node, localIndex } = nodeMapping;

        console.log("localIndex:", localIndex);

        range.setStart(node, localIndex);
        range.setEnd(node, localIndex);

        const globalRect = range.getBoundingClientRect();
        const textRect = textRef.getBoundingClientRect();

        const x = globalRect.x - textRect.x + paddingLeft;
        const y = globalRect.y - textRect.y + paddingTop;
        console.log("x:", x, "y:", y, "height:", globalRect.height);

        setCaretHeight2(globalRect.height);
        setCaretX2(x);
        setCaretY2(y);
      } catch (err) {
        console.error(err);
      }

      const end = performance.now();
      console.timeStamp(`time: ${end - start}ms`);
      console.groupEnd();
    });

    const end = performance.now();
    console.timeStamp(`time: ${end - start}ms`);
    console.groupEnd();
  });

  return (
    <div class="size-full flex flex-col p-2">
      <div
        ref={containerRef}
        tabIndex="0"
        class="-outline-offset-1 outline-theme-colors-aqua-base focus-within:outline-1 relative p-2"
        onMouseDown={(e) => {
          // prevent gaining focus on click
          e.preventDefault();
        }}
        onClick={() => {
          textAreaRef.focus();
        }}
        onFocusIn={() => {
          if (document.activeElement !== textAreaRef) textAreaRef.focus();
        }}
        onFocusOut={() => {
          textAreaRef.blur();
        }}
        onKeyDown={(e) => {
          if (e.key === "Escape") textAreaRef.blur();
        }}
      >
        <textarea
          ref={textAreaRef}
          tabIndex="-1"
          class="absolute p-0 border-0 size-0 overflow-hidden whitespace-nowrap"
          style={{ clip: "rect(0px, 0px, 0px, 0px)" }}
          autocomplete="off"
          autocorrect="off"
          onFocusIn={() => {
            console.log("text area focus");
          }}
          onKeyDown={(ev) => {
            /* eslint-disable solid/reactivity */
            console.group("textArea onKeyDown");

            Match.value(ev.key).pipe(
              Match.when("Backspace", () => {
                console.log("> backspace");

                setText(
                  text().slice(0, caretIndex() - 1) +
                    text().slice(caretIndex()),
                );
                setCaretIndex((offset) => Math.max(offset - 1, 0));
              }),
              Match.when("Enter", () => {
                console.log("> enter");

                insertText("\n");
                setCaretIndex((offset) => Math.min(offset + 1, text().length));
              }),
              Match.when("ArrowLeft", () => {
                console.log("> left");
                setCaretIndex((offset) => Math.max(offset - 1, 0));
              }),
              Match.when("ArrowRight", () => {
                console.log("> right");
                setCaretIndex((offset) => Math.min(offset + 1, text().length));
              }),
              Match.orElse((key) => {
                console.log("key:", key);
              }),
            );

            console.groupEnd();
          }}
          onInput={(ev) => {
            /* eslint-disable solid/reactivity */
            console.group("textArea onInput");

            console.log("input event:", ev);
            console.log("type:", ev.type);
            console.log("inputType:", ev.inputType);
            console.log(`data: '${ev.data}'`);

            Match.value(ev.inputType).pipe(
              Match.when("insertText", () => {
                console.log("> insert");
                if (!ev.data) return;

                insertText(ev.data);
                setCaretIndex((offset) => offset + ev.data!.length);
              }),
              Match.when("insertLineBreak", () => {
                // console.log("> newline");
                // insertText("\n");
                // setCaretOffset((offset) => offset + 1);
              }),
              Match.when("deleteContentBackward", () => {
                // empty since we never get this is an empty textarea
              }),
              Match.orElse((inputType) => {
                console.warn("unknown inputType: ", inputType);
              }),
            );

            textAreaRef.value = "";

            console.groupEnd();
          }}
        />

        <div
          class="absolute w-[1px] h-4 bg-theme-colors-green-border/50"
          style={{
            left: `${caretX()}px`,
            height: `${caretHeight()}px`,
          }}
        />

        <div
          class="absolute w-[1px] h-4 bg-theme-colors-blue-border/50"
          style={{
            left: `${caretX2()}px`,
            top: `${caretY2()}px`,
            height: `${caretHeight2()}px`,
          }}
        />

        <div
          ref={textRef}
          class={cn("whitespace-pre", enableMono() && "font-mono")}
        >
          <span>{text()}</span>
        </div>
      </div>

      <hr class="my-2" />
      <div class="flex flex-col gap-2">
        caret offset: {caretIndex()}
        <label class="flex gap-1">
          <input
            type="checkbox"
            checked={enableMono()}
            onInput={({ target }) => setEnableMono(target.checked)}
          />
          Monospace
        </label>
      </div>
    </div>
  );
};

export default App;
