export const consoleGroup = (title: string, fn: () => void) => {
  console.group(title);
  fn();
  console.groupEnd();
};
export default consoleGroup;
