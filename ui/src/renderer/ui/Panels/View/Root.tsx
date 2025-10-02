import { onMount, onCleanup, VoidComponent } from "solid-js";

import { monitorForElements } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";

import { useContext } from "../Context";

import Workspace from "./Workspace";
import { handleDrop } from "./dnd";

export const Root: VoidComponent = () => {
  const ctx = useContext();

  onMount(() => {
    const cleanup = monitorForElements({
      onDrop: ({ source, location }) => {
        handleDrop(ctx, source, location);
      },
    });
    onCleanup(() => cleanup());
  });

  return <Workspace />;
};

export default Root;
