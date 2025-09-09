export function assert(condition: boolean, message?: string): asserts condition;
export function assert(
  condition: boolean,
  message: () => string,
): asserts condition;
export function assert(
  condition: boolean,
  message?: string | (() => string),
): asserts condition {
  const msg = message
    ? typeof message === "function"
      ? message()
      : message
    : "Assertion failed";
  console.assert(condition, msg);

  if (!condition) throw new Error(msg);
}

export default assert;
