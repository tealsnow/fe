export type UpdateFn<T> = (fn: (_: T) => T) => void;
export default UpdateFn;
