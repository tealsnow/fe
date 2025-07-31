// import { ParentProps } from "solid-js";

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

type PanelNodeCommon = {
  kind: PanelNodeKind;
  dbgName: string;

  parent?: PanelNode;
};

type PanelNodeLeaf = PanelNodeCommon & {
  kind: "leaf";
};

type SplitDirection = "vertical" | "horizontal";

type PanelNodeSplit = PanelNodeCommon & {
  kind: "split";
  split_direction: SplitDirection;
  children: PanelNode[];
};

type PanelNode = PanelNodeLeaf | PanelNodeSplit;

//=

const case_a = () => {
  const split_c: PanelNodeSplit = {
    kind: "split",
    dbgName: "C",
    split_direction: "horizontal",
    children: [],
  };

  const leaf_a: PanelNodeLeaf = {
    kind: "leaf",
    dbgName: "A",
  };

  const leaf_b: PanelNodeLeaf = {
    kind: "leaf",
    dbgName: "B",
  };

  leaf_a.parent = split_c;
  split_c.children.push(leaf_a);
  leaf_b.parent = split_c;
  split_c.children.push(leaf_b);

  return split_c;
};

const Panels = () => {
  return <>panels</>;
};

export default Panels;
