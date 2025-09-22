import { Accessor, Component } from "solid-js";
import { SetStoreFunction, Store } from "solid-js/store";
import { Data, Effect, Option } from "effect";
import * as tsafe from "tsafe";

import UUID, { makeUUID } from "~/lib/UUID";
import Integer from "~/lib/Integer";
import Percent from "~/lib/Percent";
import { PickPartial } from "~/lib/type_helpers";

export type PanelID = Data.TaggedEnum<{
  DockSpace: { uuid: UUID };
  Leaf: { uuid: UUID };
}>;
export namespace PanelID {
  const RawCtor = Data.taggedEnum<PanelID>();
  export const $is = RawCtor.$is;
  export const $match = RawCtor.$match;

  export type FromTag<T extends PanelID["_tag"]> = Data.TaggedEnum.Value<
    PanelID,
    T
  >;

  export type DockSpace = FromTag<"DockSpace">;
  export type Leaf = FromTag<"Leaf">;

  export const DockSpace = (): DockSpace =>
    RawCtor.DockSpace({ uuid: makeUUID() });
  export const Leaf = (): Leaf => RawCtor.Leaf({ uuid: makeUUID() });
}
tsafe.assert<tsafe.Equals<PanelID, PanelID.DockSpace | PanelID.Leaf>>();

export type PanelNode = Data.TaggedEnum<{
  DockSpace: {
    id: PanelID.DockSpace;
    layout: PanelNode.DockSpaceLayout;
  };
  Leaf: {
    id: PanelID.Leaf;
    title: Accessor<string>;
    content: () => Promise<{ default: Component<{}> }>;
  };
}> & {
  parent: Option.Option<PanelID.DockSpace>;
};
export namespace PanelNode {
  const RawCtor = Data.taggedEnum<PanelNode>();
  export const $is = RawCtor.$is;
  export const $match = RawCtor.$match;

  export type FromTag<T extends PanelNode["_tag"]> = Data.TaggedEnum.Value<
    PanelNode,
    T
  >;

  export type DockSpace = FromTag<"DockSpace">;
  export type Leaf = FromTag<"Leaf">;

  export const DockSpace = (
    opts: PickPartial<Omit<DockSpace, "_tag" | "parent">, "id"> & {
      parent?: PanelID.DockSpace;
    },
  ): DockSpace =>
    RawCtor.DockSpace({
      id: opts.id ?? PanelID.DockSpace(),
      parent: Option.fromNullable(opts.parent),
      layout: opts.layout,
    });

  export const Leaf = (
    opts: PickPartial<
      Omit<Leaf, "_tag" | "id"> & {
        parent: Option.Option.Value<Leaf["parent"]>;
      },
      "parent"
    >,
  ): Leaf =>
    RawCtor.Leaf({
      id: PanelID.Leaf(),
      parent: Option.fromNullable(opts.parent),
      title: opts.title,
      content: opts.content,
    });

  export type Root = DockSpace & {
    readonly parent: Option.None<PanelID.DockSpace>;
    readonly layout: DockSpaceLayout.Slotted;
  };

  // This is named `canBeRoot` instead of `isRoot` because nodes of this shape
  // could exist and not be root
  export const canBeRoot = (obj: PanelNode): obj is Root => {
    return (
      $is("DockSpace")(obj) &&
      Option.isNone(obj.parent) &&
      DockSpaceLayout.$is("Slotted")(obj.layout)
    );
  };

  export type DockSpaceLayout = Data.TaggedEnum<{
    Split: {
      direction: DockSpaceLayout.SplitDirection;
      children: { percent: Percent; child: PanelID }[];
    };
    Tabs: {
      active: Option.Option<Integer>;
      children: PanelID.Leaf[];
    };
    Slotted: {
      slots: Record<string, DockSpaceLayout.Slot>;
      layout: Component<{ slots: Record<string, DockSpaceLayout.Slot> }>;
      addChild: Option.Option<
        (child: PanelNode) => Effect.Effect<void, PanelAddChildError>
      >;
    };
  }>;
  export namespace DockSpaceLayout {
    export type SplitDirection = "horizontal" | "vertical";

    export type Slot = {
      name: string;
      enabled: Accessor<boolean>;
      child: Accessor<Option.Option<PanelID>>;
    };
    export const Slot = Data.case<Slot>();

    const RawCtor = Data.taggedEnum<DockSpaceLayout>();
    export const $is = RawCtor.$is;
    export const $match = RawCtor.$match;

    export type FromTag<T extends DockSpaceLayout["_tag"]> =
      Data.TaggedEnum.Value<DockSpaceLayout, T>;
    export type Split = FromTag<"Split">;
    export type Tabs = FromTag<"Tabs">;
    export type Slotted = FromTag<"Slotted">;

    export const Split = (opts: Omit<Split, "_tag" | "children">): Split =>
      RawCtor.Split({ children: [], ...opts });
    export const Tabs = (): Tabs =>
      RawCtor.Tabs({ children: [], active: Option.none() });
    export const Slotted = (
      opts: Omit<Slotted, "_tag" | "slots"> & { slots: Slot[] },
    ): Slotted =>
      RawCtor.Slotted({
        ...opts,
        slots: opts.slots.reduce((acc, slot) => {
          acc[slot.name] = slot;
          return acc;
        }, {}),
      });
  }
  tsafe.assert<
    tsafe.Equals<
      DockSpaceLayout,
      DockSpaceLayout.Split | DockSpaceLayout.Tabs | DockSpaceLayout.Slotted
    >
  >();
}
tsafe.assert<tsafe.Equals<PanelNode, PanelNode.DockSpace | PanelNode.Leaf>>();

export type PanelNodeStore = Record<UUID, PanelNode>;
export type PanelTree = {
  readonly root: PanelID.DockSpace;
  nodes: Store<PanelNodeStore>;
  setNodes: SetStoreFunction<PanelNodeStore>;
};
export const PanelTree = Data.case<PanelTree>();

export class PanelDoesNotExistError extends Data.TaggedError(
  "PanelDoesNotExistInTreeError",
)<{
  readonly id: PanelID;
}> {
  message = `Panel (with id ${this.id}) cannot be found in the node store`;
}

export class PanelAlreadyHasParentError extends Data.TaggedError(
  "PanelAlreadyHasParentError",
)<{
  readonly id: PanelID;
  readonly existing: PanelID.DockSpace;
  readonly addingTo: PanelID.DockSpace;
}> {
  message =
    `Panel (with id ${this.id}) ` +
    `already has a parent (with id ${this.existing}) - ` +
    `Failure in attempt to add to parent (with id ${this.addingTo})`;
}

export class PanelDoesNotAcceptChildError extends Data.TaggedError(
  "PanelDoesNotAcceptDockSpaceChildError",
)<{
  readonly id: PanelID;
  readonly parent: PanelID.DockSpace;
  readonly reason?: string;
}> {
  message =
    `Cannot add panel (with id ${this.id}) to parent (with id: ${this.parent})` +
    this.reason
      ? `: "${this.reason}"`
      : "";
}

export type PanelAddChildError =
  | PanelDoesNotExistError
  | PanelAlreadyHasParentError
  | PanelDoesNotAcceptChildError;

export class PanelDockSpaceIsNotTabsLayoutError extends Data.TaggedError(
  "PanelDockSpaceIsNotTabsLayoutError",
)<{
  dockSpace: PanelID.DockSpace;
}> {
  message = `DockSpace (with id ${this.dockSpace}) is not a tab layout`;
}
