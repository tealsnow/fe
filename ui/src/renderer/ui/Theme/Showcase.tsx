import { createSignal, Index, VoidComponent } from "solid-js";

import { Icon, IconKind, icons } from "~/assets/icons";

import cn from "~/lib/cn";

import Switch from "~/ui/components/Switch";

import * as Theme from "~/ui/Theme";

export const Showcase: VoidComponent = () => {
  const Colors: VoidComponent = () => {
    return (
      <>
        <div class="flex flex-col p-1 pl-4">
          <h2 class="underline underline-offset-2 text-lg">Colors</h2>
        </div>

        <div class="flex flex-row justify-evenly text-center">
          <Index each={Object.values(Theme.ColorKindSchema.enum)}>
            {(color) => {
              return (
                <div
                  class="m-1 flex size-16 flex-grow flex-row content-center
                  items-center justify-center gap-2 border-2 shadow-md"
                  style={{
                    background: `var(--theme-colors-${color()}-background)`,
                    "border-color": `var(--theme-colors-${color()}-border)`,
                  }}
                >
                  <div
                    class="size-5 border-2"
                    style={{
                      background: `var(--theme-colors-${color()}-base)`,
                      "border-color": `var(--theme-colors-${color()}-border)`,
                    }}
                  />
                  {color()}
                </div>
              );
            }}
          </Index>
        </div>
      </>
    );
  };

  const Icons: VoidComponent = () => {
    const [fill, setFill] = createSignal(true);

    return (
      <>
        <div class="flex flex-col p-1 pl-4">
          <h2 class="underline underline-offset-2 text-lg">Icons</h2>

          <Switch
            class="flex items-center gap-1 w-full"
            checked={fill()}
            onChange={() => setFill((b) => !b)}
          >
            <Switch.Control>
              <Switch.Thumb />
            </Switch.Control>

            <Switch.Label class="mr-auto">fill</Switch.Label>
          </Switch>
        </div>

        <div class="flex flex-row flex-wrap justify-evenly text-center">
          <Index each={IconKind}>
            {(kind) => {
              return (
                <div class="m-1 flex-grow flex-col content-center items-center justify-center rounded-sm p-2 text-xs shadow-md">
                  {kind()}
                  <Icon
                    icon={icons[kind()]}
                    noDefaultStyles={kind() === "fe"}
                    class={cn("size-10", !fill() && "fill-none")}
                  />
                </div>
              );
            }}
          </Index>
        </div>
      </>
    );
  };

  const ThemeSpec: VoidComponent = () => {
    return (
      <>
        <div class="flex flex-col p-1 pl-4">
          <h2 class="underline underline-offset-2 text-lg">ThemeSpec</h2>
        </div>

        <Index each={Theme.themeColorsDescFlat}>
          {(item) => {
            return (
              <div class="m-1 flex flex-row items-center gap-1">
                <div
                  class="size-6 border border-black"
                  style={{
                    background: `var(--theme-${item().join("-")})`,
                  }}
                />
                <p class="font-mono">{item().join("-")}</p>
              </div>
            );
          }}
        </Index>
      </>
    );
  };

  return (
    <div class="flex-col overflow-auto w-full">
      <Colors />
      <Icons />
      <ThemeSpec />
    </div>
  );
};
