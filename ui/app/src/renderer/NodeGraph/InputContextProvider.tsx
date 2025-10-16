import { ParentComponent, useContext } from "solid-js";
import { createStore } from "solid-js/store";
import { DocumentEventListener } from "@solid-primitives/event-listener";
import { Match } from "effect";

import { InputContext } from "./InputContext";

export const useInputContext = (): InputContext => {
  const ctx = useContext(InputContext);
  if (!ctx)
    throw new Error(
      "Cannot use Input Context outside of a Input Context Provider",
    );
  return ctx;
};

export const InputContextProvider: ParentComponent<{}> = (props) => {
  const [inputState, setInputState] = createStore<InputContext>({
    shift: false,
    ctrl: false,
    alt: false,
    space: false,
    leftMouseButton: false,
  });

  return (
    <InputContext.Provider value={inputState}>
      <DocumentEventListener
        onKeydown={(ev) => {
          // console.log(`key down - key: '${ev.key}' code: '${ev.code}'`);

          Match.value(ev.key).pipe(
            Match.when("Shift", () => setInputState("shift", true)),
            Match.when("Control", () => setInputState("ctrl", true)),
            Match.when("Alt", () => setInputState("alt", true)),
            Match.when(" ", () => setInputState("space", true)),
            // Match.orElse((key) => {
            // }),
          );
        }}
        onKeyup={(ev) => {
          Match.value(ev.key).pipe(
            Match.when("Shift", () => setInputState("shift", false)),
            Match.when("Control", () => setInputState("ctrl", false)),
            Match.when("Alt", () => setInputState("alt", false)),
            Match.when(" ", () => setInputState("space", false)),
          );
        }}
        onMousedown={(ev) => {
          console.log(
            `mouse down - button: '${ev.button}' buttons: '${ev.buttons}'`,
          );

          Match.value(ev.button).pipe(
            Match.when(0, () => setInputState("leftMouseButton", true)),
            // Match.when(1, () => "middle"),
            // Match.when(2, () => "right"),
          );
        }}
        onMouseup={(ev) => {
          Match.value(ev.button).pipe(
            Match.when(0, () => setInputState("leftMouseButton", false)),
            // Match.when(1, () => "middle"),
            // Match.when(2, () => "right"),
          );
        }}
      />

      {props.children}
    </InputContext.Provider>
  );
};
