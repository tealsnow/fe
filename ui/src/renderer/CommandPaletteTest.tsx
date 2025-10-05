import { createSignal, VoidComponent } from "solid-js";
import { DocumentEventListener } from "@solid-primitives/event-listener";

import { Match } from "effect";

import Command from "~/ui/components/Command";

import Dialog from "~/ui/components/Dialog";
import Button from "~/ui/components/Button";

const CommandPaletteTest: VoidComponent = () => {
  const [open, setOpen] = createSignal(false);

  let commandRef: HTMLDivElement | undefined;

  return (
    <div class="flex p-2 items-center gap-2">
      <DocumentEventListener
        onKeypress={(e) => {
          if (e.ctrlKey && e.key === "k") setOpen(true);
        }}
      />
      <Dialog open={open()} onOpenChange={setOpen}>
        <Dialog.Trigger as={Button} class="size-fit">
          Open
        </Dialog.Trigger>
        <kbd>Ctrl-K</kbd>
        <Dialog.Content
          noCloseButton
          class="border-0 w-1/2 bg-none shadow-none max-h-1/2"
        >
          <Command
            ref={commandRef}
            label="Command Palette"
            loop
            onKeyDown={(e) => {
              if (e.target === commandRef) {
                Match.value(e.key).pipe(
                  Match.when("Escape", () => {
                    setOpen(false);
                  }),
                  // Match.when("j", () => {
                  //   console.log("down");
                  // }),
                  // Match.when("k", () => {
                  //   console.log("up");
                  // }),
                );
              } else {
                if (e.key === "Escape") {
                  commandRef?.focus();
                  e.preventDefault();
                  return;
                }
              }
            }}
          >
            <Command.Input placeholder="Type a command or search..." />
            <Command.List>
              <Command.Empty>No results found.</Command.Empty>

              <Command.Group heading="Suggestions">
                <Command.Item
                  onSelect={() => {
                    console.log("calender selected");
                  }}
                >
                  <span>Calender</span>
                </Command.Item>
                <Command.Item keywords={["face"]}>
                  <span>Search Emoji</span>
                </Command.Item>
                <Command.Item disabled>
                  <span>Launch</span>
                </Command.Item>
              </Command.Group>

              <Command.Separator />

              <Command.Group heading="Settings">
                <Command.Item>
                  <span>Profile</span>
                  <Command.Shortcut>Ctrl-P</Command.Shortcut>
                </Command.Item>
                <Command.Item>
                  <span>Mail</span>
                  <Command.Shortcut>Ctrl-B</Command.Shortcut>
                </Command.Item>
                <Command.Item>
                  <span>Open Settings</span>
                  <Command.Shortcut>Ctrl-S</Command.Shortcut>
                </Command.Item>
              </Command.Group>
            </Command.List>
          </Command>
        </Dialog.Content>
      </Dialog>
    </div>
  );
};

export default CommandPaletteTest;
