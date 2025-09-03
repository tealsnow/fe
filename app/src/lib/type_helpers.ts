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
 *
 * @template T Type to make partial
 *
 * @returns A partial of `T` recursively
 */
export type DeepPartial<T> = T extends object
  ? {
      [P in keyof T]?: T[P] extends object ? DeepPartial<T[P]> : T[P];
    }
  : T;

/**
 * @template T Type to get optional keys of
 * @returns All optional keys of a type
 */
export type OptionalKeysOf<T extends object> = Exclude<
  {
    [K in keyof T]: T extends Record<K, T[K]> ? never : K;
  }[keyof T],
  undefined
>;

/**
 * @template T object to pick optional keys of
 * @returns Creates a type of `T` only containing the optional keys
 */
export type PickOptional<T extends object> = Pick<T, OptionalKeysOf<T>>;

export type DeepWriteable<T> = {
  -readonly [P in keyof T]: DeepWriteable<T[P]>;
};
