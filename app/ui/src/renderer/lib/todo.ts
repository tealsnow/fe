import assert from "./assert";

export const todo = (msg?: string): never => {
  assert(false, `TODO${msg ? `: ${msg}` : ""}`);
};
