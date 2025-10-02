import { Component } from "solid-js";

export const LeafContent: Component<{
  render: () => Component<{}>;
}> = (props) => {
  return (
    <div class="flex relative w-full h-full" data-panel-leaf-content-root>
      {/* using absolute is the only way I have found to completely ensure that
          the rendered content cannot affect the outside sizing - breaking the
          whole panel layout system */}
      <div class="absolute left-0 right-0 top-0 bottom-0 overflow-auto">
        {props.render()({})}
      </div>
    </div>
  );
};

export default LeafContent;
