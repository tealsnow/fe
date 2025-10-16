/* eslint-disable solid/reactivity */

import {
  createSignal,
  VoidComponent,
  createEffect,
  Accessor,
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
  lineIndex: number;
  lineOffset: number;
};

type TextBuffer = {
  store: TextBufferStore;

  length: () => number;
  // offset: () => number;
  // lineOffset: () => [lineIdx: number, offsetInLine: number];

  insert: (str: string) => void;
  backspace: () => void;
  newline: () => void;

  moveLeft: () => void;
  moveRight: () => void;
  moveUp: () => void;
  moveDown: () => void;
};

const TextBuffer = (initialText?: string): TextBuffer => {
  const [store, setStore] = createStore<TextBufferStore>({
    lines: initialText ? initialText.split("\n") : [],
    lineIndex: 0,
    lineOffset: 0,
  });

  // const [lines, setLines] = createStore<string[]>(
  //   initialText ? initialText.split("\n") : [],
  // );

  const length = createMemo(() => {
    let len = 0;
    for (const line of store.lines) len += line.length + 1;
    return len;
  });

  // const lineIndex = createSignal(number)

  // const [offset, setOffset] = createSignal(length());

  // const lineOffset = createMemo<[lineIdx: number, offsetInLine: number]>(() => {
  //   const off = offset();
  //   let idx = 0;
  //   let lineIdx = 0;
  //   for (const line of lines) {
  //     idx += line.length;
  //     if (idx > off) {
  //       return [lineIdx, idx - off];
  //     }
  //     lineIdx += 1;
  //   }
  //   return [0, 0];
  // });

  const insert = (str: string): void => {
    batch(() => {
      if (str.includes("\n")) {
        console.log("TODO");
        return;
      }

      setStore(
        "lines",
        store.lineIndex,
        (text) =>
          text.slice(0, store.lineOffset) + str + text.slice(store.lineOffset),
      );
      setStore("lineOffset", (offset) => offset + str.length);
    });
  };

  const backspace = (): void => {
    batch(() => {
      if (store.lineOffset === 0) {
        console.warn("TODO");
        return;
      }

      setStore(
        "lines",
        store.lineIndex,
        (text) =>
          text.slice(0, store.lineOffset - 1) + text.slice(store.lineOffset),
      );
      setStore("lineOffset", (offset) => offset - 1);
    });
  };

  const newline = (): void => {
    batch(() => {
      setStore("lines", (lines) => {
        const line = lines[store.lineIndex]!;

        const left = line.slice(0, store.lineOffset);
        const right = line.slice(store.lineOffset);

        const before = lines.slice(0, store.lineIndex);
        const after = lines.slice(store.lineIndex + 1);

        return [...before, left, right, ...after];
      });
      setStore("lineIndex", (idx) => idx + 1);
      setStore("lineOffset", 0);
    });
  };

  const moveLeft = (): void => {
    if (store.lineOffset === 0) {
      console.warn("TODO");
      return;
    }
    setStore("lineOffset", (offset) => offset - 1);
  };
  const moveRight = (): void => {
    const line = store.lines[store.lineIndex]!;
    if (line.length === store.lineOffset) {
      console.warn("TODO");
      return;
    }

    setStore("lineOffset", (offset) => offset + 1);
  };
  const moveUp = (): void => {
    if (store.lineIndex === 0) return;
    setStore("lineIndex", (idx) => idx - 1);
  };
  const moveDown = (): void => {
    if (store.lines.length - 1 === store.lineIndex) return;

    batch(() => {
      const line = store.lines[store.lineIndex + 1]!;
      setStore("lineIndex", (idx) => idx + 1);
      setStore("lineOffset", (offset) =>
        Order.clamp(Number.Order)({ minimum: 0, maximum: line.length })(offset),
      );
    });
  };

  return {
    store,
    length,
    // offset,
    // lineOffset,

    insert,
    backspace,
    newline,

    moveLeft,
    moveRight,
    moveUp,
    moveDown,
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
  const buffer = TextBuffer("some existing text\nmultiline");

  const insertCharWidth = 1;

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
      const lineOffset = buffer.store.lineOffset;

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
        onClick={(ev) => {
          if (!focused()) textAreaRef.focus();

          // const point = document.caretPositionFromPoint(ev.x, ev.y);
          // if (point?.offset) setCaretIndex(point.offset);
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
                buffer.backspace();

                // setText(
                //   text().slice(0, caretIndex() - 1) +
                //     text().slice(caretIndex()),
                // );
                // setCaretIndex((offset) => Math.max(offset - 1, 0));
              }),
              Match.when("Enter", () => {
                console.log("> enter");
                buffer.newline();

                // insertText("\n");
                // setCaretIndex((offset) => Math.min(offset + 1, text().length));
              }),
              Match.when("ArrowLeft", () => {
                console.log("> left");
                buffer.moveLeft();

                // setCaretIndex((offset) => Math.max(offset - 1, 0));
              }),
              Match.when("ArrowRight", () => {
                console.log("> right");
                buffer.moveRight();

                // setCaretIndex((offset) => Math.min(offset + 1, text().length));
              }),
              Match.when("ArrowUp", () => {
                console.log("> up");
                buffer.moveUp();
              }),
              Match.when("ArrowDown", () => {
                console.log("> down");
                buffer.moveDown();
              }),
              Match.orElse((key) => {
                console.log("unhandled key:", key);
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

                // insertText(ev.data);
                // setCaretIndex((offset) => offset + ev.data!.length);
                buffer.insert(ev.data);
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

        <Show when={focused()}>
          <div
            class="absolute bg-theme-colors-green-border/50"
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
            {(line) => (
              <span>
                {line}
                {"\n"}
              </span>
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
          line offset: <pre>{buffer.store.lineOffset}</pre>
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
