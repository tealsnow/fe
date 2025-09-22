import { Brand } from "effect";

export type Percent = number & Brand.Brand<"Percent">;

const PercentRaw = Brand.refined<Percent>(
  (n) => Number.isFinite(n) && n >= 0 && n <= 1,
  (n) => Brand.error(`Expected ${n} to be a percentage`),
);

export const from = (num: number): Percent => Percent(num / 100);

export const Percent = Object.assign(PercentRaw, {
  from,
});

export default Percent;
