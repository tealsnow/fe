/**
 * https://github.com/tc39/proposal-math-clamp
 */

declare global {
  interface Math {
    clamp(value: number, min: number, max: number): number;
  }
}

Math.clamp = (val: number, min: number, max: number): number => {
  return Math.min(Math.max(min, val), max);
};
