import { batch, Component, createEffect, Index, onMount } from "solid-js";
import { Console, Effect, Option } from "effect";

import Percent from "~/lib/Percent";
import UUID from "~/lib/UUID";
import assert from "~/lib/assert";
import Integer from "~/lib/Integer";

import {
  LeafRecord,
  PanelNode,
  LeafID,
  LeafContent,
  WorkspaceSidebars,
  WorkspaceSidebar,
} from "./data";
import { PanelContextProvider, usePanelContext } from "./ContextProvider";
import View from "./View";

export const Test: Component<{}> = () => {
  // const leftId = LeafID.make();
  // // const rightId = LeafID.make();
  // const bottomId = LeafID.make();

  // const testTab1Id = LeafID.make();
  // const testTab2Id = LeafID.make();

  // const rightTopId = LeafID.make();
  // // const rightBottomId = LeafID.make();
  // const rightBottomLeftId = LeafID.make();
  // const rightBottomRightId = LeafID.make();

  // const leafRecord: LeafRecord = {
  //   [leftId]: LeafContent({
  //     title: "left panel",
  //     render: () => <>left panel content</>,
  //   }),
  //   // [rightId]: LeafContent({
  //   //   title: "right panel",
  //   //   render: () => <>right panel content</>,
  //   // }),
  //   [bottomId]: LeafContent({
  //     title: "bottom panel",
  //     render: () => <>bottom panel content</>,
  //   }),

  //   [testTab1Id]: LeafContent({
  //     title: "test tab 1",
  //     render: () => {
  //       const ctx = usePanelContext();

  //       const rightSplit = ctx.workspace.sidebars.right.node;
  //       // assert(PanelNode.$is("Split")(rightSplit));

  //       return (
  //         <div class="flex grow flex-col overflow-auto">
  //           <pre>{JSON.stringify(rightSplit, null, 2)}</pre>
  //           {/*<Index each={rightSplit.children}>
  //             {(child, idx) => {
  //               return (
  //                 <p>
  //                   {idx} - {child().percent * 100} %
  //                 </p>
  //               );
  //             }}
  //           </Index>*/}
  //         </div>
  //       );
  //     },
  //   }),
  //   [testTab2Id]: LeafContent({
  //     title: "test tab 2",
  //     render: () => <>test tab 2 content</>,
  //   }),

  //   [rightTopId]: LeafContent({
  //     title: "right top",
  //     render: () => <>right top content</>,
  //   }),
  //   // [rightBottomId]: LeafContent({
  //   //   title: "right bottom",
  //   //   render: () => <>right bottom content</>,
  //   // }),
  //   [rightBottomLeftId]: LeafContent({
  //     title: "right bottom left",
  //     render: () => <>right bottom left content</>,
  //   }),
  //   [rightBottomRightId]: LeafContent({
  //     title: "right bottom right",
  //     render: () => <>right bottom right content</>,
  //   }),
  // };

  return (
    <div class="flex grow overflow-hidden">
      <PanelContextProvider
      // initial={{
      //   workspace: {
      //     root: PanelNode.Tabs({
      //       active: Option.none(),
      //       children: [
      //         PanelNode.Leaf({ id: testTab1Id }),
      //         PanelNode.Leaf({ id: testTab2Id }),
      //       ],
      //     }),
      //     sidebars: WorkspaceSidebars({
      //       left: WorkspaceSidebar({
      //         enabled: false,
      //         node: PanelNode.Leaf({ id: leftId }),
      //       }),
      //       right: WorkspaceSidebar({
      //         enabled: true,
      //         size: Percent.from(40),
      //         // node: PanelNode.Leaf({ id: rightId }),
      //         node: PanelNode.makeSplit({
      //           axis: "vertical",
      //           children: [
      //             PanelNode.Leaf({ id: rightTopId }),
      //             // PanelNode.Leaf({ id: rightBottomId }),
      //             PanelNode.makeSplit({
      //               axis: "horizontal",
      //               children: [
      //                 PanelNode.Leaf({ id: rightBottomLeftId }),
      //                 PanelNode.Leaf({ id: rightBottomRightId }),
      //               ],
      //             }),
      //           ],
      //         }),
      //       }),
      //       bottom: WorkspaceSidebar({
      //         enabled: true,
      //         node: PanelNode.Leaf({ id: bottomId }),
      //       }),
      //     }),
      //   },
      //   leafRecord: leafRecord,
      // }}
      >
        <ActualTest />
      </PanelContextProvider>
    </div>
  );
};

const ActualTest: Component = () => {
  const ctx = usePanelContext();

  onMount(() => {
    batch(() => {
      ctx.setWorkspace({
        root: PanelNode.makeTabs({
          active: Integer(0),
          children: [
            ctx.createLeaf({
              title: "right split dbg",
              render: () => {
                const rightSplit = ctx.workspace.sidebars.right.node;
                return (
                  <div class="flex grow flex-col overflow-auto p-1">
                    <pre>{JSON.stringify(rightSplit, null, 2)}</pre>
                  </div>
                );
              },
            }),
            ctx.createLeaf({
              title: "test tab",
              render: () => <></>,
            }),
            ctx.createLeaf(),
          ],
        }),
        sidebars: {
          left: WorkspaceSidebar({
            enabled: false,
            node: ctx.createLeaf(),
          }),
          right: WorkspaceSidebar({
            enabled: true,
            node: PanelNode.makeSplit({
              axis: "vertical",
              children: [
                ctx.createLeaf({
                  title: "right top",
                  render: () => <>right top content</>,
                }),
                PanelNode.makeSplit({
                  axis: "horizontal",
                  children: [
                    ctx.createLeaf({
                      title: "right bottom left",
                      render: () => <>right bottom left</>,
                    }),
                    ctx.createLeaf({
                      title: "right bottom right",
                      render: () => <>right bottom right</>,
                    }),
                  ],
                }),
              ],
            }),
          }),
          bottom: WorkspaceSidebar({
            enabled: true,
            node: ctx.createLeaf(),
          }),
        },
      });
    });
  });

  return (
    <>
      <View.Workspace />
    </>
  );
};
