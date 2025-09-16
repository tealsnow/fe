import {
  Accessor,
  Component,
  createContext,
  createSignal,
  ParentProps,
  Setter,
  useContext,
} from "solid-js";
import * as Panel from "./Panel";
import { createStore } from "solid-js/store";
import { Option } from "effect";
import effectEdgeRunSync from "~/lib/effectEdgeRunSync";

export type PanelContext = {
  tree: Panel.Tree;
  setTree: Panel.SetTree;
  dbg: {
    selectedId: Accessor<Option.Option<Panel.ID>>;
    setSelectedId: Setter<Option.Option<Panel.ID>>;
  };
};
export const PanelContext = createContext<PanelContext>();

export const usePanelContext = (): PanelContext => {
  const ctx = useContext(PanelContext);
  if (!ctx) throw new Error("usePanels must be used within a PanelsProvider");
  return ctx;
};

export type PanelContextProviderProps = ParentProps<{
  initialTitlebar?: Component<{}>;
}>;
export const PanelContextProvider: Component<PanelContextProviderProps> = (
  props,
) => {
  const existing = useContext(PanelContext);
  if (existing) throw new Error("Cannot nest `PanelsContext`s");

  const [tree, setTree] = createStore<Panel.Tree>(
    Panel.Tree.create({
      titlebar: props.initialTitlebar,
    }).pipe(effectEdgeRunSync),
  );

  const [selectedId, setSelectedId] = createSignal<Option.Option<Panel.ID>>(
    Option.none(),
  );

  return (
    <PanelContext.Provider
      value={{
        tree,
        setTree,
        dbg: {
          selectedId,
          setSelectedId,
        },
      }}
    >
      {props.children}
    </PanelContext.Provider>
  );
};
