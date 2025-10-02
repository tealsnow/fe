import { ParentComponent } from "solid-js";
import { cn } from "~/lib/cn";

export const PanelTitlebar: ParentComponent<{
  class?: string;
}> = (props) => {
  let ref!: HTMLDivElement;
  return (
    <div data-panel-titlebar-root class="min-h-6 max-h-6 relative">
      <div
        ref={ref}
        class={cn(
          "absolute left-0 right-0 top-0 bottom-0 flex flex-row items-center border-theme-border border-b overflow-x-scroll no-scrollbar",
          props.class,
        )}
        onWheel={(ev) => {
          // @HACK: This is real hacky, I find it hard to believe that there is
          //   no way to scroll horizontally by default on the web platform.
          //   Again this is a hack. I know at the native level it knows if it is
          //   discrete or not, so I hate having to check like this.
          //   Further on large lists, with multiple notches from a scroll wheel
          //   the scrollBy with smooth breaks and starts jittering
          //   The cleanest solution is to just have the `+=`s with the delta,
          //   only problem is that it it stops the smooth scroll.
          //   If we are so inclined, we could do so with a custom smooth scroll
          //   implementation, which may be needed for to be made other parts
          //   of the application.

          ev.preventDefault();

          const isDiscrete = Math.abs(ev.deltaY) < 50;

          if (isDiscrete) {
            ref.scrollLeft += ev.deltaY;
            ref.scrollLeft += ev.deltaX;
          } else {
            ref.scrollBy({ left: ev.deltaY, behavior: "smooth" });
          }
        }}
      >
        {props.children}
      </div>
    </div>
  );
};
export default PanelTitlebar;
