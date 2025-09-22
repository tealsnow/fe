import {
  PanelContext,
  PanelContextProvider,
  PanelContextProviderProps,
  usePanelContext,
} from "./context";
import {
  PanelID,
  PanelNode,
  PanelNodeStore,
  PanelTree,
  PanelDoesNotExistError,
  PanelAlreadyHasParentError,
  PanelDoesNotAcceptChildError,
  PanelAddChildError,
  PanelDockSpaceIsNotTabsLayoutError,
} from "./data";
import { Render as PanelRender } from "./Render";

export namespace Panel {
  export type Context = PanelContext;

  export type ContextProviderProps = PanelContextProviderProps;
  export const ContextProvider = PanelContextProvider;

  export const useContext = usePanelContext;

  export import ID = PanelID;
  export import Node = PanelNode;
  export type NodeStore = PanelNodeStore;
  export type Tree = PanelTree;

  export const Render = PanelRender;

  export type DoesNotExistError = PanelDoesNotExistError;
  export const DoesNotExistError = PanelDoesNotExistError;

  export type AlreadyHasParentError = PanelAlreadyHasParentError;
  export const AlreadyHasParentError = PanelAlreadyHasParentError;

  export type DoesNotAcceptChildError = PanelDoesNotAcceptChildError;
  export const DoesNotAcceptChildError = PanelDoesNotAcceptChildError;

  export type AddChildError = PanelAddChildError;

  export type DockSpaceIsNotTabsLayoutError =
    PanelDockSpaceIsNotTabsLayoutError;
  export const DockSpaceIsNotTabsLayoutError =
    PanelDockSpaceIsNotTabsLayoutError;
}

export default Panel;
