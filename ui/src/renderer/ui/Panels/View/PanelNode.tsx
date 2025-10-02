import { Component, Switch } from "solid-js";
import { Option } from "effect";

import MatchTag from "~/lib/MatchTag";
import assert from "~/lib/assert";
import UpdateFn from "~/lib/UpdateFn";

import { PanelNode, SplitAxis } from "../data";

import ViewPanelNodeSplit from "./PanelNodeSplit";
import ViewPanelNodeTabs from "./PanelNodeTabs";

export const ViewPanelNode: Component<{
  node: () => PanelNode;
  updateNode: UpdateFn<PanelNode>;
  parentSplitAxis: () => Option.Option<SplitAxis>;
}> = (props) => {
  return (
    <Switch>
      <MatchTag on={props.node()} tag={"Split"}>
        {(split) => (
          <ViewPanelNodeSplit
            split={split}
            updateSplit={(fn) =>
              props.updateNode((node) => {
                assert(PanelNode.$is("Split")(node));
                return fn(node);
              })
            }
          />
        )}
      </MatchTag>
      <MatchTag on={props.node()} tag={"Tabs"}>
        {(tabs) => (
          <ViewPanelNodeTabs
            tabs={tabs}
            updateTabs={(fn) =>
              props.updateNode((node) => {
                assert(PanelNode.$is("Tabs")(node));
                return fn(node);
              })
            }
            parentSplitAxis={props.parentSplitAxis}
          />
        )}
      </MatchTag>
    </Switch>
  );
};

export default ViewPanelNode;
