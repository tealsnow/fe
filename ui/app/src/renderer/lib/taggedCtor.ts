import { Data } from "effect";

export const isTagged = <A extends { _tag: string }>(
  value: any,
  tag: A["_tag"],
): value is A => {
  if (value._tag === tag) return true;
  return false;
};

export const taggedCtor = <A extends { readonly _tag: string }>(
  tag: A["_tag"],
): Data.Case.Constructor<A, "_tag"> & { $is: (value: any) => value is A } =>
  Object.assign(Data.tagged<A>(tag), {
    $is: (value: any) => isTagged<A>(value, tag),
  });
