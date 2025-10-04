import type {
  Component,
  ComponentProps,
  ParentComponent,
  VoidComponent,
} from "solid-js";
import { splitProps } from "solid-js";

import type { DialogRootProps } from "@kobalte/core/dialog";
import * as CommandPrimitive from "cmdk-solid";

import { cn } from "~/lib/cn";
import Dialog from "~/ui/components/Dialog";
import Noise from "./Noise";

const CommandRoot: ParentComponent<CommandPrimitive.CommandRootProps> = (
  props,
) => {
  const [local, others] = splitProps(props, ["class", "children"]);

  return (
    <CommandPrimitive.CommandRoot
      class={cn(
        "flex size-full flex-col overflow-hidden rounded-md bg-theme-background text-theme-text blur-none border-theme-border border shadow-md",
        local.class,
      )}
      {...others}
    >
      <Noise class="size-full">{local.children}</Noise>
    </CommandPrimitive.CommandRoot>
  );
};

const CommandDialog: ParentComponent<DialogRootProps> = (props) => {
  const [local, others] = splitProps(props, ["children"]);

  return (
    <Dialog {...others}>
      <Dialog.Content class="overflow-hidden p-0">
        <CommandRoot class="[&_[cmdk-group-heading]]:px-2 [&_[cmdk-group-heading]]:font-medium [&_[cmdk-group-heading]]:text-muted-foreground [&_[cmdk-group]:not([hidden])_~[cmdk-group]]:pt-0 [&_[cmdk-input-wrapper]_svg]:size-5 [&_[cmdk-input]]:h-12 [&_[cmdk-item]]:px-2 [&_[cmdk-item]]:py-3 [&_[cmdk-item]_svg]:size-5">
          {local.children}
        </CommandRoot>
      </Dialog.Content>
    </Dialog>
  );
};

const CommandInput: VoidComponent<CommandPrimitive.CommandInputProps> = (
  props,
) => {
  const [local, others] = splitProps(props, ["class"]);

  return (
    <div
      class="flex items-center border-theme-border border-b px-3"
      cmdk-input-wrapper=""
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
        class="mr-2 size-4 shrink-0 opacity-50"
      >
        <path d="M10 10m-7 0a7 7 0 1 0 14 0a7 7 0 1 0 -14 0" />
        <path d="M21 21l-6 -6" />
      </svg>
      <CommandPrimitive.CommandInput
        class={cn(
          "flex h-8 w-full rounded-md bg-transparent px-1 text-sm outline-none border-0 ring-0 placeholder:text-theme-deemphasis disabled:cursor-not-allowed disabled:opacity-50",
          local.class,
        )}
        {...others}
      />
    </div>
  );
};

const CommandList: ParentComponent<CommandPrimitive.CommandListProps> = (
  props,
) => {
  const [local, others] = splitProps(props, ["class"]);

  return (
    <CommandPrimitive.CommandList
      class={cn("max-h-[300px] overflow-y-auto overflow-x-hidden", local.class)}
      {...others}
    />
  );
};

const CommandEmpty: ParentComponent<CommandPrimitive.CommandEmptyProps> = (
  props,
) => {
  const [local, others] = splitProps(props, ["class"]);

  return (
    <CommandPrimitive.CommandEmpty
      class={cn("py-6 text-center text-sm", local.class)}
      {...others}
    />
  );
};

const CommandGroup: ParentComponent<CommandPrimitive.CommandGroupProps> = (
  props,
) => {
  const [local, others] = splitProps(props, ["class"]);

  return (
    <CommandPrimitive.CommandGroup
      class={cn(
        "overflow-hidden p-1 text-theme-text [&_[cmdk-group-heading]]:px-2 [&_[cmdk-group-heading]]:py-1.5 [&_[cmdk-group-heading]]:text-xs [&_[cmdk-group-heading]]:font-medium [&_[cmdk-group-heading]]:text-theme-deemphasis",
        local.class,
      )}
      {...others}
    />
  );
};

const CommandSeparator: VoidComponent<
  CommandPrimitive.CommandSeparatorProps
> = (props) => {
  const [local, others] = splitProps(props, ["class"]);

  return (
    <CommandPrimitive.CommandSeparator
      class={cn("h-px mx-2 bg-theme-border", local.class)}
      {...others}
    />
  );
};

const CommandItem: ParentComponent<CommandPrimitive.CommandItemProps> = (
  props,
) => {
  const [local, others] = splitProps(props, ["class"]);

  return (
    <CommandPrimitive.CommandItem
      cmdk-item=""
      class={cn(
        "relative flex cursor-default select-none items-center rounded-sm px-2 py-1.5 text-sm outline-none aria-selected:bg-theme-icon-base-fill data-[disabled=true]:pointer-events-none data-[disabled=true]:opacity-50",
        local.class,
      )}
      {...others}
    />
  );
};

const CommandShortcut: Component<ComponentProps<"span">> = (props) => {
  const [local, others] = splitProps(props, ["class"]);

  return (
    <kbd
      class={cn(
        "ml-auto text-xs tracking-widest text-theme-deemphasis",
        local.class,
      )}
      {...others}
    />
  );
};

export {
  CommandRoot,
  CommandDialog,
  CommandInput,
  CommandList,
  CommandEmpty,
  CommandGroup,
  CommandItem,
  CommandShortcut,
  CommandSeparator,
};

const Command = Object.assign(CommandRoot, {
  Dialog: CommandDialog,
  Input: CommandInput,
  List: CommandList,
  Empty: CommandEmpty,
  Group: CommandGroup,
  Item: CommandItem,
  Shortcut: CommandShortcut,
  Separator: CommandSeparator,
});
export default Command;
