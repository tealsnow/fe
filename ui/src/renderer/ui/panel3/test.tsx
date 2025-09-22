import { Component, createEffect } from "solid-js";
import { Console, Effect, Option } from "effect";

import { LeafRecord, PanelNode, addLeaf, LeafID, LeafContent } from "./data";
import View from "./View";
import { PanelContextProvider, usePanelContext } from "./Context";
import Percent from "~/lib/Percent";

export const Test: Component<{}> = () => {
  const leftId = LeafID.make();
  // const rightId = LeafID.make();
  const bottomId = LeafID.make();

  const testTab1Id = LeafID.make();
  const testTab2Id = LeafID.make();

  const rightTopId = LeafID.make();
  const rightBottomId = LeafID.make();

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
      render: () => <>test tab 1 content</>,
    }),
    [testTab2Id]: LeafContent({
      title: "test tab 2",
      render: () => <>test tab 2 content</>,
    }),

    [rightTopId]: LeafContent({
      title: "right top",
      render: () => <>right top content</>,
    }),
    [rightBottomId]: LeafContent({
      title: "right bottom",
      render: () => <>right bottom content</>,
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
          sidebars: {
            left: {
              enabled: false,
              node: PanelNode.Leaf({ id: leftId }),
            },
            right: {
              enabled: true,
              // node: PanelNode.Leaf({ id: rightId }),
              node: PanelNode.Split({
                axis: "vertical",
                children: [
                  {
                    percent: Percent.from(50),
                    node: PanelNode.Leaf({ id: rightTopId }),
                  },
                  {
                    percent: Percent.from(50),
                    node: PanelNode.Leaf({ id: rightBottomId }),
                  },
                ],
              }),
            },
            bottom: {
              enabled: true,
              node: PanelNode.Leaf({ id: bottomId }),
            },
          },
        }}
        initialLeafRecord={leafRecord}
      >
        <ActualTest />
      </PanelContextProvider>
    </div>
  );
};

export const ActualTest: Component<{}> = () => {
  return <View.Workspace />;
};
