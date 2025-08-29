/**
 * Creates an object with keys of `U`, being a union of strings, to value of T.
 * @template U Union of strings.
 * @template T Value type.
 *
 * @example
 * ```ts
 * type Enum = "foo" | "bar";
 *
 * type Obj = EnumMap<Enum, string>;
 * // ->
 * type Obj = {
 *   foo: string,
 *   bar: string,
 * };
 * ```
 */
export type EnumMap<U extends string, T> = {
  [K in U]: T;
};

/**
 * Acts like [`Partial`] but does so recursively
 */
export type DeepPartial<T> = T extends object
  ? {
      [P in keyof T]?: T[P] extends object ? DeepPartial<T[P]> : T[P];
    }
  : T;
