import { Effect, Option } from "effect";

export const OptionGetOrFail = <A, E>(
  option: Option.Option<A>,
  error: () => E,
): Effect.Effect<A, E> =>
  Option.getOrElse(Option.map(option, Effect.succeed), () =>
    Effect.fail(error()),
  );

export default OptionGetOrFail;
