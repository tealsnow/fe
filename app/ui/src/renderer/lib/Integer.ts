import { Brand } from "effect";

export type Integer = number & Brand.Brand<"Integer">;
export const Integer = Brand.refined<Integer>(
  (num) => Number.isInteger(num),
  (num) => Brand.error(`Expected ${num} to be an integer`),
);

export default Integer;
