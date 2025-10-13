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
    space: false,
    leftMouseButton: false,
  });

  return (
    <InputContext.Provider value={inputState}>
      <DocumentEventListener
        onKeydown={(ev) => {
          Match.value(ev.key).pipe(
            Match.when("Shift", () => setInputState("shift", true)),
            Match.when("Control", () => setInputState("ctrl", true)),
            Match.when(" ", () => setInputState("space", true)),
            Match.orElse((key) => {
              console.log(`key down '${key}'`);
            }),
          );
        }}
        onKeyup={(ev) => {
          Match.value(ev.key).pipe(
            Match.when("Shift", () => setInputState("shift", false)),
            Match.when("Control", () => setInputState("ctrl", false)),
            Match.when(" ", () => setInputState("space", false)),
          );
        }}
        onMousedown={(ev) => {
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
