import process from "process";
import { Match } from "effect";

import native from "@fe/native";
import { Platform } from "../shared/Platform";

const platform = Match.value(process.platform).pipe(
  Match.withReturnType<Platform>(),
  Match.when("linux", () => "Linux"),
  Match.when("darwin", () => "MacOS"),
  Match.when("win32", () => "Windows"),
  Match.orElse(() => "Unknown"),
);

export const api = { native, platform };
export type API = typeof api;
