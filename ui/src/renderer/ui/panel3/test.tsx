import { Component, createEffect, Index } from "solid-js";
import { Console, Effect, Option } from "effect";

import Percent from "~/lib/Percent";
import UUID from "~/lib/UUID";

import {
  LeafRecord,
  PanelNode,
  addLeaf,
  LeafID,
  LeafContent,
  WorkspaceSidebars,
  WorkspaceSidebar,
} from "./data";
import { PanelContextProvider, usePanelContext } from "./Context";
import View from "./View";
import assert from "~/lib/assert";

export const Test: Component<{}> = () => {
  const leftId = LeafID.make();
  // const rightId = LeafID.make();
  const bottomId = LeafID.make();

  const testTab1Id = LeafID.make();
  const testTab2Id = LeafID.make();

  const rightTopId = LeafID.make();
  // const rightBottomId = LeafID.make();
  const rightBottomLeftId = LeafID.make();
  const rightBottomRightId = LeafID.make();

  const leafRecord: LeafRecord = {
    [leftId]: LeafContent({
      title: "left panel",
      render: () => <>left panel content</>,
    }),
    // [rightId]: LeafContent({
    //   title: "right panel",
    //   render: () => <>right panel content</>,
    // }),
    [bottomId]: LeafContent({
      title: "bottom panel",
      render: () => <>bottom panel content</>,
    }),

    [testTab1Id]: LeafContent({
      title: "test tab 1",
      render: () => {
        const ctx = usePanelContext();

        const rightSplit = ctx.workspace.sidebars.right.node;
        // assert(PanelNode.$is("Split")(rightSplit));

        return (
          <div class="flex flex-col">
            <pre>{JSON.stringify(rightSplit, null, 2)}</pre>
            {/*<Index each={rightSplit.children}>
              {(child, idx) => {
                return (
                  <p>
                    {idx} - {child().percent * 100} %
                  </p>
                );
              }}
            </Index>*/}
          </div>
        );
      },
    }),
    [testTab2Id]: LeafContent({
      title: "test tab 2",
      render: () => <>test tab 2 content</>,
    }),

    [rightTopId]: LeafContent({
      title: "right top",
      render: () => <>right top content</>,
    }),
    // [rightBottomId]: LeafContent({
    //   title: "right bottom",
    //   render: () => <>right bottom content</>,
    // }),
    [rightBottomLeftId]: LeafContent({
      title: "right bottom left",
      render: () => <>right bottom left content</>,
    }),
    [rightBottomRightId]: LeafContent({
      title: "right bottom right",
      render: () => <>right bottom right content</>,
    }),
  };

  return (
    <div class="flex grow overflow-hidden">
      <PanelContextProvider
        initialWorkspace={{
          root: PanelNode.Tabs({
            active: Option.none(),
            children: [
              PanelNode.Leaf({ id: testTab1Id }),
              PanelNode.Leaf({ id: testTab2Id }),
            ],
          }),
          sidebars: WorkspaceSidebars({
            left: WorkspaceSidebar({
              enabled: false,
              node: PanelNode.Leaf({ id: leftId }),
            }),
            right: WorkspaceSidebar({
              enabled: true,
              size: Percent.from(40),
              // node: PanelNode.Leaf({ id: rightId }),
              node: PanelNode.makeSplit({
                axis: "vertical",
                children: [
                  PanelNode.Leaf({ id: rightTopId }),
                  // PanelNode.Leaf({ id: rightBottomId }),
                  PanelNode.makeSplit({
                    axis: "horizontal",
                    children: [
                      PanelNode.Leaf({ id: rightBottomLeftId }),
                      PanelNode.Leaf({ id: rightBottomRightId }),
                    ],
                  }),
                ],
              }),
            }),
            bottom: WorkspaceSidebar({
              enabled: true,
              node: PanelNode.Leaf({ id: bottomId }),
            }),
          }),
        }}
        initialLeafRecord={leafRecord}
      >
        <View.Workspace />
      </PanelContextProvider>
    </div>
  );
};
