import { Match } from "effect";

import { SnapKind, SnapConfig, GridSize } from "./Config";

export type Coords = [number, number];

export const coordsSnapToGrid = ([x, y]: Coords, snapTo: number): Coords => [
  Math.round(x / snapTo) * snapTo,
  Math.round(y / snapTo) * snapTo,
];

export const snapKindToNumber = (kind: SnapKind): number =>
  Match.value(kind).pipe(
    Match.whenOr("none", "disabled", () => 1),
    Match.when("1s", () => GridSize),
    Match.when("5s", () => GridSize * 5),
    Match.exhaustive,
  );

export const snapKindForConfig = (
  config: SnapConfig,
  mods: { ctrl: boolean; shift: boolean },
): SnapKind =>
  Match.value(mods).pipe(
    Match.withReturnType<SnapKind>(),
    Match.when({ ctrl: true, shift: true }, () => config.ctrlShift),
    Match.when({ ctrl: true, shift: false }, () => config.ctrl),
    Match.when({ ctrl: false, shift: true }, () => config.shift),
    Match.when({ ctrl: false, shift: false }, () => config.default),
    Match.exhaustive,
  );
