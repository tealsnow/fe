import { Data } from "effect";
import Integer from "./Integer";

export class OutOfBoundsError extends Data.TaggedError("OutOfBoundsError")<{
  index: Integer;
}> {
  message = `Index ${this.index} is out of bounds`;
}
export default OutOfBoundsError;
