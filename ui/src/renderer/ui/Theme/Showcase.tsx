import { Index, VoidComponent } from "solid-js";

import { Icon, iconKinds, icons } from "~/assets/icons";

import * as Theme from "~/ui/Theme";

export const Showcase: VoidComponent = () => {
  const Colors: VoidComponent = () => {
    return (
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
    );
  };

  const Icons: VoidComponent = () => {
    return (
      <div class="flex flex-row flex-wrap justify-evenly text-center">
        <Index each={iconKinds}>
          {(kind) => {
            return (
              <div
                class="m-1 flex-grow flex-col content-center items-center
                  justify-center rounded-sm p-2 text-xs shadow-md"
              >
                {kind()}
                <Icon
                  icon={icons[kind()]}
                  noDefaultStyles={kind() === "fe"}
                  class="size-10"
                />
              </div>
            );
          }}
        </Index>
      </div>
    );
  };

  return (
    <div class="flex-col overflow-auto w-full">
      <Colors />
      <Icons />
      <Index each={Theme.themeColorsDescFlat}>
        {(item) => {
          return (
            <div
              class="m-1 flex flex-row items-center gap-2 border border-black
                p-1"
            >
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
    </div>
  );
};
