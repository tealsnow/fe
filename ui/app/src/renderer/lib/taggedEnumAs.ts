import { Data, Option } from "effect";

export const taggedEnumAs = <E extends { _tag: string }, T extends E["_tag"]>(
  tag: T,
): ((taggedEnum: unknown) => Option.Option<Data.TaggedEnum.Value<E, T>>) => {
  return (taggedEnum) => {
    if (!!taggedEnum && (taggedEnum as any)._tag === tag)
      return Option.some(taggedEnum as Data.TaggedEnum.Value<E, T>);
    return Option.none();
  };
};

export default taggedEnumAs;
