import * as z from "zod";

/**
 * Flatten an array of objects into a single object.
 * e.g. `[{ a: 1 }, { b: 2 }]` => `{ a: 1, b: 2 }`
 */
export const flattenArrayOfObjects = function <
  InputValue,
  OutputValue,
  Input extends Record<keyof any, InputValue> | {},
  Output extends Record<keyof any, OutputValue> | {},
>(array: Input[]): Output {
  return array.reduce<Output>((acc, obj) => ({ ...acc, ...obj }), {} as Output);
};

declare global {
  interface Array<T> {
    flatten<
      InputValue,
      OutputValue,
      Input extends Record<keyof any, InputValue>,
      Output extends Record<keyof any, OutputValue>,
    >(
      this: Input[],
    ): Output;
  }
}

/**
 * Flatten an array of objects into a single object.
 * e.g. `[{ a: 1 }, { b: 2 }]` => `{ a: 1, b: 2 }`
 */
Array.prototype.flatten = function <
  InputValue,
  OutputValue,
  Input extends Record<keyof any, InputValue> | {},
  Output extends Record<keyof any, OutputValue> | {},
>(this: Input[]): Output {
  return flattenArrayOfObjects(this);
};

/**
 * Flatten a generic object into a list of leaf paths,
 * e.g. `{ foo: { bar: {}, baz: { a: {}, b: {} }, }, quux: {} }`
 * becomes [["foo", "bar"], ["foo", "baz", "a"], ["foo", "bar", "b"] ["quux"]]
 */
export const flattenObjectToPaths = (
  obj: Record<string, any>,
  prefix: string[] = [],
): string[][] => {
  const paths: string[][] = [];

  for (const key in obj) {
    const value = obj[key];
    const currentPath = [...prefix, key];

    if (value && typeof value === "object" && !Array.isArray(value)) {
      const subPaths = flattenObjectToPaths(value, currentPath);
      paths.push(...subPaths);
    } else {
      paths.push(currentPath);
    }
  }

  // Special case for `{}` leaf objects
  if (Object.keys(obj).length === 0) {
    paths.push(prefix);
  }

  return paths;
};

/**
 * Acts the same as [`flattenObjectToPaths`] but takes a zod schema instead
 */
export function flattenZodSchemaPaths(
  schema: z.ZodTypeAny,
  prefix: string[] = [],
): string[][] {
  if (schema instanceof z.ZodObject) {
    const shape = schema.shape;

    return Object.entries(shape).flatMap(([key, value]) => {
      return flattenZodSchemaPaths(value, [...prefix, key]);
    });
  }

  return [prefix];
}
