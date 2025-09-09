import {
  Component,
  createEffect,
  createMemo,
  createSignal,
  JSX,
  onCleanup,
  onMount,
  ParentProps,
} from "solid-js";
import {
  draggable,
  dropTargetForElements,
  monitorForElements,
} from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { match } from "ts-pattern";
import { createStore } from "solid-js/store";

import { IconKind, Icon } from "~/assets/icons";
import { cn } from "~/lib/cn";
import { Brand } from "effect";

export type Coord = [number, number];

export type PieceType = "king" | "pawn";

export type PieceRecord = {
  type: PieceType;
  location: Coord;
};

export const isCoordEqual = (a: Coord, b: Coord): boolean => {
  return a[0] === b[0] && a[1] === b[1];
};

export const pieceIconLookup: {
  [Key in PieceType]: IconKind;
} = {
  king: "bell",
  pawn: "close",
};

type PieceDragData = {
  location: Coord;
  type: PieceType;
} & Brand.Brand<"PieceDragData">;
const PieceDragData = Brand.nominal<PieceDragData>();

const isPieceDragData = (obj: any): obj is PieceDragData => {
  return PieceDragData.is(obj);
};

type SinglePieceProps = {
  location: Coord;
};

type PieceProps = SinglePieceProps & {
  type: PieceType;
};

const Piece = (props: PieceProps) => {
  const [dragging, setDragging] = createSignal<boolean>(false);

  let ref!: HTMLDivElement;
  onMount(() => {
    // setup element to be dragged
    // we provide some data for other listeners to get the info for
    // the "source"
    const cleanup = draggable({
      element: ref,

      getInitialData: () =>
        PieceDragData({
          location: props.location,
          type: props.type,
        }) as any,

      onDrag: () => setDragging(true),
      onDrop: () => setDragging(false),
    });
    onCleanup(() => cleanup());
  });

  return (
    <div
      ref={ref}
      class={cn(
        "h-[45px] w-[45px] rounded-md p-1 hover:bg-gray-600",
        dragging() && "opacity-50",
      )}
    >
      <Icon kind={pieceIconLookup[props.type]} />
    </div>
  );
};

type DrawPiece = Component<SinglePieceProps>;

const King = (props: SinglePieceProps) => {
  return <Piece type="king" location={props.location} />;
};

const Pawn = (props: SinglePieceProps) => {
  return <Piece type="pawn" location={props.location} />;
};

export const pieceLookup: {
  [Key in PieceType]: DrawPiece;
} = {
  king: (props: SinglePieceProps) => <King location={props.location} />,
  pawn: (props: SinglePieceProps) => <Pawn location={props.location} />,
};

const canMove = (
  type: PieceType,
  src: Coord,
  dst: Coord,
  pieces: PieceRecord[],
): boolean => {
  if (pieces.find((p) => isCoordEqual(p.location, dst))) return false;

  const rowDist = Math.abs(src[0] - dst[0]);
  const colDist = Math.abs(src[1] - dst[1]);

  return match(type)
    .returnType<boolean>()
    .with("king", () => {
      return [rowDist, colDist].every((dist) => [0, 1].includes(dist));
    })
    .with("pawn", () => {
      return colDist === 0 && src[0] - dst[0] === -1;
    })
    .exhaustive();
};

type SquareDragData = {
  location: Coord;
} & Brand.Brand<"SquareDragData">;
const SquareDragData = Brand.nominal<SquareDragData>();

const isSquareDragData = (obj: any): obj is SquareDragData => {
  return SquareDragData.is(obj);
};

type SquareProps = ParentProps<{
  location: Coord;
  pieces: PieceRecord[];
}>;

const Square = (props: SquareProps) => {
  type SquareHoverState = "idle" | "valid" | "invalid";

  let ref!: HTMLDivElement;
  const [state, setState] = createSignal<SquareHoverState>("idle");

  onMount(() => {
    // setup this element as a place where we can drop elements
    // we provide data for monitorForElements to learn about it from
    // the "destination"
    // has access to "source"s and is able to determine if they can or
    // cannot be dropped here
    // doesn't handle the drop itself
    const cleanup = dropTargetForElements({
      element: ref,

      getData: () =>
        SquareDragData({
          location: props.location,
        }) as any,

      canDrop: ({ source }) => {
        if (!isPieceDragData(source.data)) return false;

        return !isCoordEqual(source.data.location, props.location);
      },
      onDragEnter: ({ source }) => {
        if (!isPieceDragData(source.data)) return;

        if (
          canMove(
            source.data.type,
            source.data.location,
            props.location,
            props.pieces,
          )
        )
          setState("valid");
        else setState("invalid");
      },
      onDragLeave: () => setState("idle"),
      onDrop: () => setState("idle"),
    });
    onCleanup(() => cleanup());
  });

  const isDark = createMemo(() => {
    const [row, col] = props.location;
    return (row + col) % 2 === 1;
  });

  return (
    <div
      ref={ref}
      class={cn(
        "flex size-full items-center justify-center",
        isDark() ? "bg-gray-500" : "bg-gray-50",
        match(state())
          .with("idle", () => undefined)
          .with("valid", () => "bg-green-400")
          .with("invalid", () => "bg-red-400")
          .exhaustive(),
      )}
    >
      {props.children}
    </div>
  );
};

const renderSquares = (pieces: PieceRecord[]) => {
  const squares: JSX.Element[] = [];
  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      const location: Coord = [row, col];
      const piece = pieces.find((piece) =>
        isCoordEqual(piece.location, location),
      );
      squares.push(
        <Square location={location} pieces={pieces}>
          {piece && pieceLookup[piece.type]({ location })}
        </Square>,
      );
    }
  }
  return squares;
};

const Chessboard = () => {
  const [pieces, setPieces] = createStore<PieceRecord[]>([
    { type: "king", location: [3, 2] },
    { type: "pawn", location: [1, 6] },
  ]);

  createEffect(() => {
    // orchestrates the whole dnd system
    // has access to both "source" and "destination"
    // handles the actual drop and state update
    const cleanup = monitorForElements({
      onDrop: ({ source, location }) => {
        const destination = location.current.dropTargets[0];
        if (!destination) return;

        if (!isPieceDragData(source.data)) return;
        if (!isSquareDragData(destination.data)) return;
        const srcData = source.data;
        const dstData = destination.data;

        const piece = pieces.find((p) =>
          isCoordEqual(p.location, srcData.location),
        );

        if (
          canMove(srcData.type, srcData.location, dstData.location, pieces) &&
          piece !== undefined
        ) {
          const otherPieces = pieces.filter((p) => p !== piece);
          setPieces([
            { type: piece.type, location: dstData.location },
            ...otherPieces,
          ]);
        }
      },
    });
    onCleanup(() => cleanup());
  });

  return (
    <div class="grid h-[500px] w-[500px] grid-cols-8 grid-rows-8 border-4 border-solid border-gray-400">
      {renderSquares(pieces)}
    </div>
  );
};

export const DND = () => {
  return <Chessboard />;
};

export default DND;
