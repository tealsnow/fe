import { ParentComponent, Show } from "solid-js";
import cn from "~/lib/cn";

export const Noise: ParentComponent<{
  class?: string;
  enabled?: boolean;
}> = (props) => {
  return (
    <div class={cn("relative bg-theme-background", props.class)}>
      <Show when={props.enabled ?? true}>
        <svg
          class="absolute left-0 right-0 top-0 bottom-0 size-full inset-0 pointer-events-none"
          style={{ opacity: 0.3, "mix-blend-mode": "soft-light" }}
        >
          <filter id="noiseFilter" x={0} y={0} width="100%" height="100%">
            <feTurbulence
              type="fractalNoise"
              // type="turbulence"
              baseFrequency="0.32"
              numOctaves={2}
              stitchTiles="stitch"
              result="turbulence"
            />
            <feComponentTransfer in="turbulence" result="darken">
              <feFuncR type="linear" slope="0.8" intercept="0" />
              <feFuncG type="linear" slope="0.8" intercept="0" />
              <feFuncB type="linear" slope="0.8" intercept="0" />
            </feComponentTransfer>
            <feDisplacementMap
              in="sourceGraphic"
              in2="darken"
              scale={25}
              xChannelSelector="R"
              yChannelSelector="G"
              result="displacement"
            />
            <feBlend
              mode="multiply"
              in="sourceGraphic"
              in2="displacement"
              result="multiply"
            />
            <feColorMatrix in="multiply" type="saturate" values="0" />
          </filter>

          <rect
            width="100%"
            height="100%"
            filter="url(#noiseFilter)"
            fill="transparent"
          />
        </svg>
      </Show>

      {props.children}
    </div>
  );
};

export default Noise;
