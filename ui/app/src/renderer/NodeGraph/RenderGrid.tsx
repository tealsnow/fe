import { VoidComponent, createEffect } from "solid-js";

import cn from "~/lib/cn";
import { ElementSize } from "~/lib/createElementSize";

import { GridStyle, GridSize } from "./Config";
import { Coords } from "./coords";

type DrawGridFn = (args: {
  ctx: CanvasRenderingContext2D;
  borderColor: string;
  size: ElementSize;
  originOffset: Coords;
  zoom: number;
}) => void;

const drawGridLines: DrawGridFn = ({
  ctx,
  borderColor,
  size,
  originOffset: [ox, oy],
  zoom,
}) => {
  ctx.strokeStyle = borderColor;
  ctx.lineWidth = 1;

  const scaledGrid = GridSize * zoom;

  for (let kx = Math.ceil((0 - ox) / scaledGrid); ; kx++) {
    const x = Math.round(ox + kx * scaledGrid) + 0.5;
    if (x > size.width) break;

    const alpha = kx % 50 === 0 ? 0.8 : kx % 5 === 0 ? 0.5 : 0.2;
    ctx.globalAlpha = alpha;
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, size.height);
    ctx.stroke();
  }

  for (let ky = Math.ceil((0 - oy) / scaledGrid); ; ky++) {
    const y = Math.round(oy + ky * scaledGrid) + 0.5;
    if (y > size.height) break;

    const alpha = ky % 50 === 0 ? 0.8 : ky % 5 === 0 ? 0.5 : 0.2;
    ctx.globalAlpha = alpha;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(size.width, y);
    ctx.stroke();
  }
};

const drawGridDotMatrix: DrawGridFn = ({
  ctx,
  borderColor,
  size,
  originOffset: [ox, oy],
  zoom,
}) => {
  const r5s = 1;
  const a5s = 0.6;
  const r25s = 2;
  const a25s = 0.8;

  ctx.fillStyle = borderColor;

  const step = 5 * GridSize * zoom;

  const kxStart = Math.ceil((0 - ox) / step);
  const kxEnd = Math.floor((size.width - ox) / step);
  const kyStart = Math.ceil((0 - oy) / step);
  const kyEnd = Math.floor((size.height - oy) / step);

  for (let kx = kxStart; kx <= kxEnd; kx++) {
    const x = Math.round(ox + kx * step) + 0.5;

    for (let ky = kyStart; ky <= kyEnd; ky++) {
      const y = Math.round(oy + ky * step) + 0.5;

      const globalXUnits = kx * 5;
      const globalYUnits = ky * 5;

      if (globalXUnits % 25 === 0 && globalYUnits % 25 === 0) {
        ctx.globalAlpha = a25s;
        ctx.beginPath();
        ctx.arc(x, y, r25s, 0, Math.PI * 2);
        ctx.fill();
      } else {
        ctx.globalAlpha = a5s;
        ctx.beginPath();
        ctx.arc(x, y, r5s, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }
};

const drawGrid: Record<GridStyle, DrawGridFn> = {
  grid_lines: drawGridLines,
  dot_matrix: drawGridDotMatrix,
};

export const RenderGrid: VoidComponent<{
  class?: string;
  gridStyle: () => GridStyle;
  size: () => ElementSize;
  offset: () => Coords;
  zoom: () => number;
}> = (props) => {
  let canvasRef!: HTMLCanvasElement;

  createEffect(() => {
    const drawFn = drawGrid[props.gridStyle()];

    // no need to fetch a new drawFn if the size or offset changes
    createEffect(() => {
      const ctx = canvasRef.getContext("2d");
      if (!ctx) {
        console.error("no canvas context");
        return;
      }

      createEffect(() => {
        const size = props.size();
        const originOffset = props.offset();
        const zoom = props.zoom();

        const styles = getComputedStyle(canvasRef);
        const borderColor = styles.getPropertyValue("--theme-border");

        ctx.clearRect(0, 0, canvasRef.width, canvasRef.height);

        drawFn({ ctx, borderColor, size, originOffset, zoom });
      });
    });
  });

  return (
    <canvas
      ref={canvasRef}
      class={cn(
        "absolute left-0 right-0 top-0 bottom-0 pointer-events-none",
        props.class,
      )}
      width={props.size().width}
      height={props.size().height}
    >
      {/* intentionally left blank */}
    </canvas>
  );
};
