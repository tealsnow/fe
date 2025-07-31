import { JSX } from "solid-js/h/jsx-runtime";
import { v4 as uuidv4 } from "uuid";

export type Workspace = {
  uuid: string;
  title: string;
  render: () => JSX.Element;
};

export type WorkspaceState = {
  workspaces: Workspace[];
  activeIndex: number | undefined;
};

export const mkWorkspace = (props: {
  title: string;
  render: () => JSX.Element;
}): Workspace => {
  return {
    uuid: uuidv4(),
    title: props.title,
    render: props.render,
  };
};

export const mkTestWorkspace = (title: string): Workspace => {
  return mkWorkspace({
    title,
    render: () => {
      return <p>{title}</p>;
    },
  });
};
