export const GridSize = 10;

export const ZoomMinMax = {
  min: 0.2,
  max: 5,
};

export type Config = {
  snapping: {
    canvas: SnapConfig;
    nodes: SnapConfig;
  };
  snapNodeSizesToGrid: boolean;
  gridStyle: GridStyle;
};
export const ConfigDefault: Config = {
  snapping: {
    canvas: {
      default: "none",
      shift: "1s",
      ctrl: "5s",
      ctrlShift: "disabled",
    },
    nodes: {
      default: "1s",
      shift: "none",
      ctrl: "5s",
      ctrlShift: "disabled",
    },
  },
  snapNodeSizesToGrid: true,
  gridStyle: "grid_lines",
};

export const SnapKind = ["none", "1s", "5s", "disabled"] as const;
export type SnapKind = (typeof SnapKind)[number];

export type SnapConfig = {
  default: SnapKind;
  ctrl: SnapKind;
  shift: SnapKind;
  ctrlShift: SnapKind;
};

export const GridStyle = ["grid_lines", "dot_matrix"] as const;
export type GridStyle = (typeof GridStyle)[number];
export const GridStyleNames: Record<GridStyle, string> = {
  grid_lines: "Lines",
  dot_matrix: "Dot matrix",
};
