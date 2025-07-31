import {
  Component,
  createEffect,
  createSignal,
  onMount,
  ParentProps,
} from "solid-js";
import { IconKind, Icon } from "./assets/icons";
import {
  draggable,
  dropTargetForElements,
  monitorForElements,
} from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import clsx from "clsx";
import { match } from "ts-pattern";
import { createStore } from "solid-js/store";

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

export const pieceLookup: {
  [Key in PieceType]: DrawPeice;
} = {
  king: (props: SinglePieceProps) => <King location={props.location} />,
  pawn: (props: SinglePieceProps) => <Pawn location={props.location} />,
};

type SinglePieceProps = {
  location: Coord;
};

type PieceProps = {
  type: PieceType;
} & SinglePieceProps;

const PieceDragDataSymbol = Symbol("PieceDragData");

type PieceDragData = {
  [PieceDragDataSymbol]: true;
  location: Coord;
  type: PieceType;
};

const isPieceDragData = (obj: any): obj is PieceDragData => {
  return obj[PieceDragDataSymbol as any];
};

const Piece = (props: PieceProps) => {
  const [dragging, setDragging] = createSignal<boolean>(false);

  let ref!: HTMLDivElement;
  onMount(() => {
    return draggable({
      element: ref,

      getInitialData: () =>
        ({
          [PieceDragDataSymbol]: true,
          location: props.location,
          type: props.type,
        }) satisfies PieceDragData,

      onDrag: () => setDragging(true),
      onDrop: () => setDragging(false),
    });
  });

  return (
    <div
      ref={ref}
      class={clsx(
        "h-[45px] w-[45px] rounded-md p-1 hover:bg-gray-600",
        dragging() && "opacity-50",
      )}
    >
      <Icon kind={pieceIconLookup[props.type]} />
    </div>
  );
};

type DrawPeice = Component<SinglePieceProps>;

const King = (props: SinglePieceProps) => {
  return <Piece type="king" location={props.location} />;
};

const Pawn = (props: SinglePieceProps) => {
  return <Piece type="pawn" location={props.location} />;
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

type SquareProps = ParentProps<{
  location: Coord;
  pieces: PieceRecord[];
}>;

type SquareHoverState = "idle" | "valid" | "invalid";

const SquareDragDataSymbol = Symbol("SquareDragData");

type SquareDragData = {
  [SquareDragDataSymbol]: true;
  location: Coord;
};

const isSquareDragData = (obj: any): obj is SquareDragData => {
  return obj[SquareDragDataSymbol as any];
};

const Square = (props: SquareProps) => {
  let ref!: HTMLDivElement;
  const [state, setState] = createSignal<SquareHoverState>("idle");

  onMount(() => {
    return dropTargetForElements({
      element: ref,

      getData: () =>
        ({
          [SquareDragDataSymbol]: true,
          location: props.location,
        }) satisfies SquareDragData,

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
  });

  const [row, col] = props.location;
  const isDark = (row + col) % 2 === 1;

  return (
    <div
      ref={ref}
      class={clsx(
        "flex size-full items-center justify-center",
        isDark ? "bg-gray-500" : "bg-gray-50",
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
  const squares = [];
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
    return monitorForElements({
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
