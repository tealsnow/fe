/* eslint-disable solid/reactivity */

/* Layers

current modal state is implemented as a set of layers, applied top to bottom
events are sent from bottom to top, stopping propagation once consumed

this works well for something like the arrow keys which should do the same thing
in both insert and normal mode, it just doesn't get overridden lower down

now which mode should be at the bottom first thought tells me normal
but I actually think it should be insert mode
make that the default - the standard mode that you should be able to do
most everything you should need to, normal mode would be a layer on top
that overrides almost all input to do normal mode things, then we can add
visual mode or whatever else on top of that.

*/

import {
  createSignal,
  VoidComponent,
  createEffect,
  Show,
  createMemo,
  batch,
  For,
} from "solid-js";
import { Match, Number, Order } from "effect";

import { cn } from "~/lib/cn";
import assert from "~/lib/assert";

import Switch from "~/ui/components/Switch";
import { createStore } from "solid-js/store";
import Button from "./ui/components/Button";

type TextBufferStore = {
  lines: string[];
  // in the range 0..=(lines.length - 1)
  lineIndex: number;
  // in the range 0..=(lines[lineIndex].length)
  columnIndex: number;

  // set on horizontal movement
  // used to maintain column during vertical movement
  // if infinity go to max
  lastColumnIndex: number;
};

type TextBuffer = {
  store: TextBufferStore;

  length: () => number;

  insert: (str: string) => void;
  deleteBackward: () => void;
  deleteForward: () => void;
  newline: () => void;

  moveLeft: () => void;
  moveRight: () => void;
  moveUp: () => void;
  moveDown: () => void;
  home: () => void;
  end: () => void;
  move: (lineIndex: number, columnIndex: number) => void;
};

const TextBuffer = (initialText?: string | string[]): TextBuffer => {
  const [store, setStore] = createStore<TextBufferStore>({
    lines: initialText
      ? typeof initialText === "string"
        ? initialText.split("\n")
        : initialText
      : [],
    lineIndex: 0,
    columnIndex: 0,
    lastColumnIndex: 0,
  });

  const length = createMemo(() => {
    let len = 0;
    for (const line of store.lines) len += line.length + 1;
    return len;
  });

  const insert: TextBuffer["insert"] = (str) =>
    batch(() => {
      if (str.includes("\n")) {
        console.log("TODO");
        return;
      }

      setStore(
        "lines",
        store.lineIndex,
        (text) =>
          text.slice(0, store.columnIndex) +
          str +
          text.slice(store.columnIndex),
      );
      setStore("columnIndex", (idx) => idx + str.length);
    });
  const deleteBackward: TextBuffer["deleteBackward"] = () =>
    batch(() => {
      if (store.columnIndex === 0) {
        if (store.lineIndex === 0) return;

        const lines = store.lines;
        const before = lines.slice(0, store.lineIndex - 1);
        const after = lines.slice(store.lineIndex + 1);

        const left = lines[store.lineIndex - 1]!;
        const right = lines[store.lineIndex]!;

        setStore("lines", () => {
          return [...before, left + right, ...after];
        });
        setStore("lineIndex", (idx) => idx - 1);
        setStore("columnIndex", left.length);
      } else {
        setStore(
          "lines",
          store.lineIndex,
          (text) =>
            text.slice(0, store.columnIndex - 1) +
            text.slice(store.columnIndex),
        );
        setStore("columnIndex", (idx) => idx - 1);
      }
    });
  const deleteForward: TextBuffer["deleteForward"] = () =>
    batch(() => {
      const line = store.lines[store.lineIndex]!;
      if (store.columnIndex === line.length) {
        setStore("lines", (lines) => {
          const before = lines.slice(0, store.lineIndex);
          const after = lines.slice(store.lineIndex + 2);

          const left = lines[store.lineIndex]!;
          const right = lines[store.lineIndex + 1];

          return [...before, left + (right ?? ""), ...after];
        });
      } else {
        setStore(
          "lines",
          store.lineIndex,
          (text) =>
            text.slice(0, store.columnIndex) +
            text.slice(store.columnIndex + 1),
        );
      }
    });
  const newline: TextBuffer["newline"] = () =>
    batch(() => {
      setStore("lines", (lines) => {
        const line = lines[store.lineIndex]!;

        const left = line.slice(0, store.columnIndex);
        const right = line.slice(store.columnIndex);

        const before = lines.slice(0, store.lineIndex);
        const after = lines.slice(store.lineIndex + 1);

        return [...before, left, right, ...after];
      });
      setStore("lineIndex", (idx) => idx + 1);
      setStore("columnIndex", 0);
    });

  const moveLeft: TextBuffer["moveLeft"] = () =>
    batch(() => {
      if (store.columnIndex === 0) {
        if (store.lineIndex === 0) return;

        setStore("lineIndex", (idx) => idx - 1);
        const line = store.lines[store.lineIndex]!;

        setStore("columnIndex", line.length);
        setStore("lastColumnIndex", store.columnIndex);
      } else {
        setStore("columnIndex", (idx) => idx - 1);
        setStore("lastColumnIndex", store.columnIndex);
      }
    });
  const moveRight: TextBuffer["moveRight"] = () =>
    batch(() => {
      const line = store.lines[store.lineIndex]!;
      if (line.length === store.columnIndex) {
        if (store.lineIndex === store.lines.length - 1) return;

        setStore("columnIndex", 0);
        setStore("lastColumnIndex", 0);
        setStore("lineIndex", (idx) => idx + 1);
      } else {
        setStore("columnIndex", (idx) => idx + 1);
        setStore("lastColumnIndex", store.columnIndex);
      }
    });
  const moveUp: TextBuffer["moveUp"] = () =>
    batch(() => {
      if (store.lineIndex === 0) {
        setStore("columnIndex", 0);
        setStore("lastColumnIndex", store.columnIndex);
      } else {
        setStore("lineIndex", (idx) => idx - 1);

        setStore("columnIndex", () => {
          const line = store.lines[store.lineIndex]!;
          return Order.clamp(Number.Order)({
            minimum: 0,
            maximum: line.length,
          })(store.lastColumnIndex);
        });
      }
    });
  const moveDown: TextBuffer["moveDown"] = () =>
    batch(() => {
      if (store.lines.length - 1 === store.lineIndex) {
        setStore("columnIndex", () => {
          const line = store.lines[store.lineIndex]!;
          return line.length;
        });
        setStore("lastColumnIndex", store.columnIndex);
      } else {
        setStore("lineIndex", (idx) => idx + 1);
        setStore("columnIndex", () => {
          const line = store.lines[store.lineIndex]!;
          return Order.clamp(Number.Order)({
            minimum: 0,
            maximum: line.length,
          })(store.lastColumnIndex);
        });
      }
    });
  const home: TextBuffer["home"] = () =>
    batch(() => {
      setStore("columnIndex", 0);
      setStore("lastColumnIndex", 0);
    });
  const end: TextBuffer["end"] = () =>
    batch(() => {
      setStore("columnIndex", store.lines[store.lineIndex]!.length);
      setStore("lastColumnIndex", Infinity);
    });
  const move: TextBuffer["move"] = (lineIndex, columnIndex) =>
    batch(() => {
      const clamp = Order.clamp(Number.Order);

      setStore(
        "lineIndex",
        clamp({ minimum: 0, maximum: store.lines.length })(lineIndex),
      );
      setStore(
        "columnIndex",
        clamp({ minimum: 0, maximum: store.lines[store.lineIndex]!.length })(
          columnIndex,
        ),
      );
      setStore("lastColumnIndex", store.columnIndex);
    });

  return {
    store,
    length,

    insert,
    deleteBackward,
    deleteForward,
    newline,

    moveLeft,
    moveRight,
    moveUp,
    moveDown,
    home,
    end,
    move,
  };
};

const TextEditingTest: VoidComponent = () => {
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
  //  - undo redo
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
  // directly through the dom, and thus is multiline aware and allows us to
  // use the DOM line breaking logic and is generally less overall work for us.
  //
  // As it stands, the DOM approach uses more code and is less performant,
  // but supports line breaking.
  //
  // The canvas approach uses less code and is more performant, but does not
  // work for multiline. We'd have to make our own solution.
  // I think for maximal control (and performance) we will go with the canvas
  // solution. It'll be more work, but I suspect we will have to do less
  // fighting with the DOM to get exactly what we want in the end.

  // text split into multiple lines
  // index for current line
  // index for where in current line
  // selection? wait until modal stuff is implemented (visual mode)?
  // this is very much a chicken and egg situation

  let containerRef!: HTMLDivElement;
  let textAreaRef!: HTMLTextAreaElement;

  let textRef!: HTMLDivElement;

  const [enableMono, setEnableMono] = createSignal(true);

  const [blockCaret, setBlockCaret] = createSignal(false);

  // const [text, setText] = createSignal("some existing text\nmultiline");
  // const [caretIndex, setCaretIndex] = createSignal(text().length);

  // const insertText = (str: string): void => {
  //   const offset = caretIndex();
  //   setText((text) => text.slice(0, offset) + str + text.slice(offset));
  // };
  // const buffer = TextBuffer("some existing text\nmultiline");

  const buffer = TextBuffer([
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
    "Sed quis tortor id nisi dapibus molestie.",
    "Aenean pellentesque tempor lacinia.",
    "Maecenas porttitor aliquam elementum.",
    "Morbi id arcu enim. Fusce mattis Morbi id arcu enim. Fusce mattis",
  ]);

  const insertCharWidth = 2;

  const [caretX, setCaretX] = createSignal(0);
  const [caretY, setCaretY] = createSignal(0);
  const [caretHeight, setCaretHeight] = createSignal(0);
  const [caretWidth, setCaretWidth] = createSignal(insertCharWidth);

  // const [caretX2, setCaretX2] = createSignal(0);
  // const [caretY2, setCaretY2] = createSignal(0);
  // const [caretHeight2, setCaretHeight2] = createSignal(0);
  // const [caretWidth2, setCaretWidth2] = createSignal(insertCharWidth);

  // document.caretPositionFromPoint

  createEffect(() => {
    console.group("canvas api caret calc - setup");
    const start = performance.now();
    performance.mark("canvas api caret calc - setup");

    enableMono(); // track font

    const textComputedStyle = getComputedStyle(textRef);
    const font = textComputedStyle.font;
    console.log("font:", font);

    const containerComputedStyle = getComputedStyle(containerRef);
    const paddingLeft = parseFloat(containerComputedStyle.paddingLeft);
    const paddingTop = parseFloat(containerComputedStyle.paddingTop);

    const canvas = document.createElement("canvas");
    const context = canvas.getContext("2d")!;
    context.font = font;

    const lineHeight = parseFloat(textComputedStyle.lineHeight);
    setCaretHeight(lineHeight);

    createEffect(() => {
      console.group("canvas api caret calc");
      const start = performance.now();

      const line = buffer.store.lines[buffer.store.lineIndex]!;
      const lineOffset = buffer.store.columnIndex;

      const textToCaret = line.slice(0, lineOffset);
      const measure = context.measureText(textToCaret);

      const x = paddingLeft + measure.width;
      const y = paddingTop + lineHeight * buffer.store.lineIndex;
      console.log("x:", x, "y:", y);
      setCaretX(x);
      setCaretY(y);

      // const fontBoundingBoxAscent = measure.fontBoundingBoxAscent;
      // const fontBoundingBoxDescent = measure.fontBoundingBoxDescent;
      // const fontHeight = fontBoundingBoxAscent + fontBoundingBoxDescent;

      if (blockCaret()) {
        const currentChar = line[lineOffset];
        const measure = context.measureText(currentChar ?? " ");
        const width = measure.width;
        setCaretWidth(width);
      } else {
        setCaretWidth(insertCharWidth);
      }

      // const textToCaret = text().slice(0, caretIndex());
      // const measure = context.measureText(textToCaret);

      // const x = measure.width + leftPadding;
      // console.log("x:", x);
      // setCaretX(x);

      // if (blockCaret()) {
      //   const currentChar = text()[caretIndex()];
      //   const measure = context.measureText(currentChar ?? " ");
      //   const width = measure.width;
      //   setCaretWidth(width);
      // } else {
      //   setCaretWidth(insertCharWidth);
      // }

      const end = performance.now();
      console.timeStamp(`time: ${end - start}ms`);
      console.groupEnd();
    });

    const end = performance.now();
    console.timeStamp(`time: ${end - start}ms`);
    console.groupEnd();
  });

  // const mapIndexToNode = (
  //   index: number,
  // ): { node: Node; localIndex: number } | null => {
  //   let cumulativeOffset = 0;

  //   const walker = document.createTreeWalker(
  //     textRef,
  //     NodeFilter.SHOW_TEXT,
  //     null,
  //   );

  //   let currentNode: Node | null;
  //   for (; (currentNode = walker.nextNode()); currentNode != null) {
  //     assert(currentNode.nodeType === Node.TEXT_NODE);

  //     const nodeTextLength = currentNode.nodeValue?.length ?? 0;

  //     if (cumulativeOffset + nodeTextLength >= index) {
  //       const localIndex = index - cumulativeOffset;
  //       return { node: currentNode, localIndex };
  //     }

  //     cumulativeOffset += nodeTextLength;
  //   }

  //   if (cumulativeOffset > 0) {
  //     const node = currentNode || walker.lastChild();
  //     if (!node) return null;
  //     return {
  //       node,
  //       localIndex: node.nodeValue?.length ?? 0,
  //     };
  //   }

  //   return null;
  // };

  // createEffect(() => {
  //   console.group("document range caret calc - setup");
  //   const start = performance.now();

  //   enableMono(); // track font

  //   const containerComputedStyle = getComputedStyle(containerRef);
  //   const paddingLeft = parseFloat(containerComputedStyle.paddingLeft);
  //   const paddingTop = parseFloat(containerComputedStyle.paddingTop);

  //   const range = document.createRange();

  //   createEffect(() => {
  //     console.group("document range caret calc");
  //     const start = performance.now();

  //     try {
  //       const nodeMapping = mapIndexToNode(caretIndex());

  //       if (!nodeMapping) {
  //         console.warn("empty line?");
  //         return;
  //       }

  //       const { node, localIndex } = nodeMapping;

  //       console.log("localIndex:", localIndex);

  //       range.setStart(node, localIndex);
  //       range.setEnd(node, localIndex);

  //       const globalRect = range.getBoundingClientRect();
  //       const textRect = textRef.getBoundingClientRect();

  //       const x = globalRect.x - textRect.x + paddingLeft;
  //       const y = globalRect.y - textRect.y + paddingTop;
  //       console.log("x:", x, "y:", y, "height:", globalRect.height);

  //       setCaretHeight2(globalRect.height);
  //       setCaretX2(x);
  //       setCaretY2(y);

  //       if (blockCaret()) {
  //         if (localIndex === text().length) {
  //           range.setStart(node, localIndex - 1);
  //           range.setEnd(node, localIndex);
  //         } else {
  //           range.setStart(node, localIndex);
  //           range.setEnd(node, localIndex + 1);
  //         }

  //         const lastCharRect = range.getBoundingClientRect();
  //         setCaretWidth2(lastCharRect.width);
  //       } else {
  //         setCaretWidth2(insertCharWidth);
  //       }
  //     } catch (err) {
  //       console.error(err);
  //     }

  //     const end = performance.now();
  //     console.timeStamp(`time: ${end - start}ms`);
  //     console.groupEnd();
  //   });

  //   const end = performance.now();
  //   console.timeStamp(`time: ${end - start}ms`);
  //   console.groupEnd();
  // });

  const [focused, setFocused] = createSignal(false);

  return (
    <div class="size-full flex flex-col p-2">
      <div
        ref={containerRef}
        // tabIndex="0"
        class="-outline-offset-1 outline-theme-colors-aqua-base focus-within:outline-1 relative p-2"
        onMouseDown={(ev) => {
          ev.preventDefault();
        }}
        onClick={() => {
          if (!focused()) textAreaRef.focus();
        }}
        onFocusIn={() => {
          // textAreaRef.focus();
        }}
        onFocusOut={() => {
          // textAreaRef.blur();
        }}
        onKeyDown={(e) => {
          if (e.key === "Escape") textAreaRef.blur();
        }}
      >
        <textarea
          ref={textAreaRef}
          tabIndex="0"
          class="absolute p-0 border-0 size-0 overflow-hidden whitespace-nowrap"
          style={{ clip: "rect(0px, 0px, 0px, 0px)" }}
          autocomplete="off"
          autocorrect="off"
          onFocusIn={() => {
            console.log("text area focus");
            setFocused(true);
          }}
          onFocusOut={() => {
            setFocused(false);
          }}
          onKeyDown={(ev) => {
            console.group("textArea onKeyDown");

            Match.value(ev.key).pipe(
              Match.when("Backspace", () => {
                console.log("> backspace");
                buffer.deleteBackward();
              }),
              Match.when("Delete", () => {
                console.log("> delete");
                buffer.deleteForward();
              }),
              Match.when("Enter", () => {
                console.log("> enter");
                buffer.newline();
              }),
              Match.when("ArrowLeft", () => {
                console.log("> left");
                buffer.moveLeft();
              }),
              Match.when("ArrowRight", () => {
                console.log("> right");
                buffer.moveRight();
              }),
              Match.when("ArrowUp", () => {
                console.log("> up");
                buffer.moveUp();
              }),
              Match.when("ArrowDown", () => {
                console.log("> down");
                buffer.moveDown();
              }),
              Match.when("Home", () => {
                console.log("> home");
                buffer.home();
              }),
              Match.when("End", () => {
                console.log("> end");
                buffer.end();
              }),
              Match.orElse((key) => {
                console.log("unhandled key:", key);
                console.log("unhandled key code:", ev.code);
              }),
            );

            console.groupEnd();
          }}
          onInput={(ev) => {
            console.group("textArea onInput");

            console.log("input event:", ev);
            console.log("type:", ev.type);
            console.log("inputType:", ev.inputType);
            console.log(`data: '${ev.data}'`);

            Match.value(ev.inputType).pipe(
              Match.when("insertText", () => {
                console.log("> insert");
                if (!ev.data) return;
                buffer.insert(ev.data);
              }),
              Match.when("insertFromPaste", () => {
                if (!ev.data) return;
                buffer.insert(ev.data);
              }),
              Match.when("insertLineBreak", () => {
                //
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

        <Show when={focused()}>
          <div
            class="absolute bg-theme-colors-aqua-base/75"
            style={{
              left: `${caretX()}px`,
              top: `${caretY()}px`,
              height: `${caretHeight()}px`,
              width: `${caretWidth()}px`,
            }}
          />

          {/*<div
            class="absolute bg-theme-colors-blue-border/50"
            style={{
              left: `${caretX2()}px`,
              top: `${caretY2()}px`,
              height: `${caretHeight2()}px`,
              width: `${caretWidth2()}px`,
            }}
          />*/}
        </Show>

        <div
          ref={textRef}
          class={cn(
            "flex flex-col whitespace-pre cursor-text selection:bg-theme-selection ",
            enableMono() && "font-mono",
          )}
        >
          <For each={buffer.store.lines}>
            {(line, idx) => (
              <div
                class="w-full"
                onClick={(ev) => {
                  const point = document.caretPositionFromPoint(ev.x, ev.y);
                  if (!point) return;
                  console.log("point:", point, "line: ", idx());
                  buffer.move(idx(), point?.offset);
                }}
              >
                <Show when={line.length === 0}>
                  {/* @HACK: so that empty lines are not ignored */}
                  <span> </span>
                </Show>
                <span class="whitespace-pre">{line}</span>
              </div>
            )}
          </For>
          {/*<span>{text()}</span>*/}
        </div>
      </div>

      <hr class="my-2" />
      <div class="flex flex-col gap-2">
        <div class="text-sm flex flex-row items-baseline gap-1">
          {/*caret offset: <pre>{caretIndex()}</pre>*/}
          line index: <pre>{buffer.store.lineIndex}</pre>
          line offset: <pre>{buffer.store.columnIndex}</pre>
        </div>

        <div class="text-sm flex flex-row items-baseline gap-1">
          focused: <pre>{focused() ? "true" : "false"}</pre>
        </div>

        <Switch
          checked={enableMono()}
          onChange={() => setEnableMono((b) => !b)}
        >
          <Switch.Control>
            <Switch.Thumb />
          </Switch.Control>
          <Switch.Label>Monospace</Switch.Label>
        </Switch>

        <Switch
          checked={blockCaret()}
          onChange={() => setBlockCaret((b) => !b)}
        >
          <Switch.Control>
            <Switch.Thumb />
          </Switch.Control>
          <Switch.Label>Block caret</Switch.Label>
        </Switch>
      </div>

      <hr class="my-2" />

      <pre>
        {JSON.stringify(buffer.store, null, 2)}
        {/*{JSON.stringify(
          {
            caretIndex: caretIndex(),
            canvasCaret: {
              x: caretX(),
              height: caretHeight(),
              width: caretWidth(),
            },
            domCaret: {
              x: caretX2(),
              y: caretY2(),
              height: caretHeight2(),
              width: caretWidth2(),
            },
            delta: {
              x: caretX() - caretX2(),
              y: "N/A",
              height: caretHeight() - caretHeight2(),
              width: caretWidth() - caretWidth2(),
            },
          },
          null,
          2,
        )}*/}
      </pre>
    </div>
  );
};

export default TextEditingTest;
