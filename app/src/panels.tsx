// import { ParentProps } from "solid-js";

import { createSignal, For, Match, mergeProps, Show, Switch } from "solid-js";
import { match } from "ts-pattern";

import { cn } from "~/lib/cn";

// type PanelLeafLinks = {
//   parent?: PanelNode;
//   nextSibling?: PanelNode;
//   prevSibling?: PanelNode;
// };

// type PanelSplitLinks = {
//   firstChild?: PanelNode;
//   lastChild?: PanelNode;
//   // childrenCount: number;
// } & PanelLeafLinks;

// type PanelLeaf = {
//   kind: "leaf";
//   dbgName: string;
//   // content: string;
// } & PanelLeafLinks;

// type SplitDirection = "vertical" | "horizontal";

// type PanelSplit = {
//   kind: "split";
//   dbgName: string;
//   split_direction: SplitDirection;
// } & PanelSplitLinks;

// type PanelNode = PanelSplit | PanelLeaf;

// const panelSplitAddChild = (split: PanelSplit, child: PanelNode) => {
//   console.assert(child.parent === undefined);
//   console.assert(child.nextSibling === undefined);
//   console.assert(child.prevSibling === undefined);

//   child.parent = split;

//   if (split.firstChild === undefined) {
//     console.assert(split.lastChild === undefined);

//     split.firstChild = child;
//     split.lastChild = child;
//   } else {
//     console.assert(split.lastChild !== undefined);

//     const last = split.lastChild!;
//     child.prevSibling = last;
//     last.nextSibling = child;
//     split.lastChild = child;
//   }
// };

// const case_a = () => {
//   const split_c: PanelSplit = {
//     kind: "split",
//     dbgName: "C",
//     split_direction: "horizontal",
//   };

//   const leaf_a: PanelLeaf = {
//     kind: "leaf",
//     dbgName: "A",
//   };

//   const leaf_b: PanelLeaf = {
//     kind: "leaf",
//     dbgName: "B",
//   };

//   panelSplitAddChild(split_c, leaf_a);
//   panelSplitAddChild(split_c, leaf_b);

//   return split_c;
// };

// type RenderPanelLeafProps = {
//   panel: PanelLeaf;
// };

// const RenderPanelLeaf = (props: RenderPanelLeafProps) => {
//   return (
//     <div class="border-bg-4 m-2 flex border">
//       {/*  */}
//       <div class="border-green border">{props.panel.dbgName}</div>
//     </div>
//   );
// };

// type RenderPanelSplitProps = {
//   panel: PanelSplit;
// };

// const RenderPanelSplit = (props: RenderPanelSplitProps) => {

//   const children = [];
//   for (let node = props.panel.firstChild; node !== undefined; )

//   return (
//     <div class="border-bg-4 m-2 flex border">
//       <div class="border-blue border">{props.panel.dbgName}</div>
//     </div>
//   );
// };

type PanelNodeKind = "leaf" | "split";

type PanelNode = {
  kind: PanelNodeKind;
  dbgName: string;

  parent?: PanelNode;
  splitInfo?: PanelSplitInfo;
};

type PanelNodeLeaf = PanelNode & {
  kind: "leaf";
  splitInfo?: undefined;
};

type PanelNodeSplit = PanelNode & {
  kind: "split";
  splitInfo: PanelSplitInfo;
};

type PanelSplitInfo = {
  direction: SplitDirection;
  children: PanelNode[];
};

// type PanelNodeLeaf = PanelNodeCommon & {
//   kind: "leaf";
// };

type SplitDirection = "vertical" | "horizontal";

// type PanelNodeSplit = PanelNodeCommon & {
//   kind: "split";
//   split_direction: SplitDirection;
//   children: PanelNode[];
// };

// type PanelNode = PanelNodeLeaf | PanelNodeSplit;

const splitAddChild = (split: PanelNodeSplit, child: PanelNode) => {
  child.parent = split;
  split.splitInfo.children.push(child);
};

const mkPanelSplit = (
  dbgName: string,
  direction: SplitDirection,
): PanelNodeSplit => {
  return {
    kind: "split",
    dbgName,
    splitInfo: {
      direction,
      children: [],
    },
  };
};

const mkPanelLeaf = (dbgName: string): PanelNodeLeaf => {
  return {
    kind: "leaf",
    dbgName,
  };
};

//=

const case_a = () => {
  const split_c = mkPanelSplit("C", "horizontal");

  const leaf_a = mkPanelLeaf("A");
  const leaf_b = mkPanelLeaf("B");

  splitAddChild(split_c, leaf_a);
  splitAddChild(split_c, leaf_b);

  return split_c;
};

const case_b = () => {
  const split_d = mkPanelSplit("D", "horizontal");

  const leaf_a = mkPanelLeaf("A");
  const leaf_b = mkPanelLeaf("B");
  const leaf_c = mkPanelLeaf("C");

  splitAddChild(split_d, leaf_a);
  splitAddChild(split_d, leaf_b);
  splitAddChild(split_d, leaf_c);

  return split_d;
};

const case_c = () => {
  const split_a = mkPanelSplit("A", "horizontal");
  const split_b = mkPanelSplit("B", "vertical");
  const split_c = mkPanelSplit("C", "vertical");

  const leaf_a = mkPanelLeaf("a");
  const leaf_b = mkPanelLeaf("b");
  const leaf_c = mkPanelLeaf("d");
  const leaf_d = mkPanelLeaf("d");
  const leaf_e = mkPanelLeaf("e");

  splitAddChild(split_a, split_b);
  splitAddChild(split_a, split_c);

  splitAddChild(split_b, leaf_a);
  splitAddChild(split_b, leaf_b);
  splitAddChild(split_b, leaf_c);

  splitAddChild(split_c, leaf_d);
  splitAddChild(split_c, leaf_e);

  return split_a;
};

type RenderPanelLeafProps = {
  panel: PanelNodeLeaf;
};

const RenderPanelLeaf = (props: RenderPanelLeafProps) => {
  return (
    <div class="border-theme-border border-2 flex flex-1 grow p-0.5">
      {/* dbg label */}
      <p
        class="border-theme-colors-green-border bg-theme-colors-green-background
          mb-0.5 inline-block size-fit border-2 p-0.5
          hover:bg-theme-colors-green-base transition"
      >
        {props.panel.dbgName}
      </p>

      {/* leaf content */}
    </div>
  );
};

type RenderPanelSplitProps = RenderPanelProps & {
  panel: PanelNodeSplit;
};

const RenderPanelSplit = (props_: RenderPanelSplitProps) => {
  const props = mergeProps({ dbgSplitLabels: false }, props_);

  return (
    <>
      {/* dbg label */}
      <Show when={props.dbgSplitLabels}>
        <div class="flex flex-row gap-0.5">
          <p
            class="border-theme-colors-purple-border
              bg-theme-colors-purple-background mb-0.5 inline-block size-fit
              border-2 p-0.5 hover:bg-theme-colors-purple-base transition"
          >
            {props.panel.dbgName}
          </p>

          <p
            class="border-theme-colors-pink-border
              bg-theme-colors-pink-background mb-0.5 inline-block size-fit
              border-2 p-0.5 hover:bg-theme-colors-purple-base transition
              text-xs"
            onClick={() => {
              // props.panel.split_direction = match(props.panel.split_direction)
              //   .returnType<SplitDirection>()
              //   .with("horizontal", () => "vertical")
              //   .with("vertical", () => "horizontal")
              //   .exhaustive();
            }}
          >
            {"{"}
            {props.panel.splitInfo.direction}
            {"}"}
          </p>
        </div>
      </Show>

      {/* children */}
      <div
        class={cn(
          "flex flex-1 gap-0.5",
          match(props.panel.splitInfo.direction)
            .with("horizontal", () => "flex-row")
            .with("vertical", () => "flex-col")
            .exhaustive(),
        )}
      >
        <For each={props.panel.splitInfo.children}>
          {(child) => <RenderPanel {...props} panel={child} />}
        </For>
      </div>
    </>
  );
};

type RenderPanelProps = {
  panel: PanelNode;

  dbgSplitBorders?: boolean;
  dbgSplitLabels?: boolean;
};

const RenderPanel = (props_: RenderPanelProps) => {
  const props = mergeProps({ dbgSplitBorders: false }, props_);

  return (
    <div
      class={cn(
        "flex flex-1 flex-col",
        props.dbgSplitBorders &&
          props.panel.kind === "split" &&
          "border-theme-colors-purple-background border-2 p-0.5",
      )}
    >
      <Switch>
        <Match when={props.panel.kind === "leaf"}>
          <RenderPanelLeaf panel={props.panel as PanelNodeLeaf} />
        </Match>

        <Match when={props.panel.kind === "split"}>
          <RenderPanelSplit {...props} panel={props.panel as PanelNodeSplit} />
        </Match>
      </Switch>
    </div>
  );
};

const Panels = () => {
  // const a = case_a();
  // const a = case_b();
  // const [panel, setStore] = createStore(case_c());
  const panel = case_c();

  const [dbgSplitBorders, setDbgSplitBorders] = createSignal(true);
  const [dbgSplitLabels, setDbgSplitLabels] = createSignal(true);

  return (
    <div class="h-full w-full flex p-2 font-mono flex-col">
      <div class="flex flex-col gap-2 p-2 text-xs">
        <For
          each={[
            {
              get: dbgSplitBorders,
              set: setDbgSplitBorders,
              lbl: "show split borders",
            },
            {
              get: dbgSplitLabels,
              set: setDbgSplitLabels,
              lbl: "show split labels",
            },
          ]}
        >
          {({ get, set, lbl }) => (
            <label class="flex flex-row gap-1">
              <input
                type="checkbox"
                checked={get()}
                id={lbl}
                class="form-checkbox border-1 border-theme-colors-purple-border
                  bg-theme-colors-purple-background outline-0
                  checked:bg-theme-colors-purple-base ring-offset-0 ring-0"
                onChange={({ target: { checked } }) => {
                  set(checked);
                }}
              />
              {lbl}
            </label>
          )}
        </For>
      </div>
      <RenderPanel
        panel={panel}
        dbgSplitBorders={dbgSplitBorders()}
        dbgSplitLabels={dbgSplitLabels()}
      />
    </div>
  );
};

export default Panels;
