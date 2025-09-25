import { Effect, Exit } from "effect";

/**
 * @deprecated
 */
export const effectEdgeRunSync = <A, E>(effect: Effect.Effect<A, E>): A => {
  const exit = Effect.runSyncExit(effect);

  if (Exit.isFailure(exit)) {
    const msg = `failure in effectEdgeRunSync: '${exit.cause}'`;
    console.error(msg);
    throw new Error(msg);
  }

  return exit.value;
};

export default effectEdgeRunSync;
