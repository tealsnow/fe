import { lazy } from "solid-js";
import type IconComponent from "./IconComponent";

// @ts-expect-error 2322
export const Add: IconComponent = lazy(() => import("./Add"));
// @ts-expect-error 2322
export const AdwaitaWindowClose: IconComponent = lazy(() => import("./AdwaitaWindowClose"));
// @ts-expect-error 2322
export const AdwaitaWindowMaximize: IconComponent = lazy(() => import("./AdwaitaWindowMaximize"));
// @ts-expect-error 2322
export const AdwaitaWindowMinimize: IconComponent = lazy(() => import("./AdwaitaWindowMinimize"));
// @ts-expect-error 2322
export const AdwaitaWindowRestore: IconComponent = lazy(() => import("./AdwaitaWindowRestore"));
// @ts-expect-error 2322
export const Bell: IconComponent = lazy(() => import("./Bell"));
// @ts-expect-error 2322
export const ChevronRight: IconComponent = lazy(() => import("./ChevronRight"));
// @ts-expect-error 2322
export const Close: IconComponent = lazy(() => import("./Close"));
// @ts-expect-error 2322
export const DndSplitAppend: IconComponent = lazy(() => import("./DndSplitAppend"));
// @ts-expect-error 2322
export const DndSplitInsert: IconComponent = lazy(() => import("./DndSplitInsert"));
// @ts-expect-error 2322
export const DndTabsMiddle: IconComponent = lazy(() => import("./DndTabsMiddle"));
// @ts-expect-error 2322
export const DndTabsSide: IconComponent = lazy(() => import("./DndTabsSide"));
// @ts-expect-error 2322
export const Fe: IconComponent = lazy(() => import("./Fe"));
// @ts-expect-error 2322
export const FeTransparent: IconComponent = lazy(() => import("./FeTransparent"));
// @ts-expect-error 2322
export const SidebarIndicatorDisabled: IconComponent = lazy(() => import("./SidebarIndicatorDisabled"));
// @ts-expect-error 2322
export const SidebarIndicatorEnabled: IconComponent = lazy(() => import("./SidebarIndicatorEnabled"));
// @ts-expect-error 2322
export const WindowMaximize: IconComponent = lazy(() => import("./WindowMaximize"));
// @ts-expect-error 2322
export const WindowMinimize: IconComponent = lazy(() => import("./WindowMinimize"));
// @ts-expect-error 2322
export const WindowRestore: IconComponent = lazy(() => import("./WindowRestore"));
export const IconKind = ["Add", "AdwaitaWindowClose", "AdwaitaWindowMaximize", "AdwaitaWindowMinimize", "AdwaitaWindowRestore", "Bell", "ChevronRight", "Close", "DndSplitAppend", "DndSplitInsert", "DndTabsMiddle", "DndTabsSide", "Fe", "FeTransparent", "SidebarIndicatorDisabled", "SidebarIndicatorEnabled", "WindowMaximize", "WindowMinimize", "WindowRestore"] as const;

export type IconKind = (typeof IconKind)[number];

export type { IconComponent };
