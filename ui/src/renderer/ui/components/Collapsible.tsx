import * as CollapsiblePrimitive from "@kobalte/core/collapsible";

const CollapsibleRoot = CollapsiblePrimitive.Root;

const CollapsibleTrigger = CollapsiblePrimitive.Trigger;

const CollapsibleContent = CollapsiblePrimitive.Content;

export { CollapsibleRoot, CollapsibleTrigger, CollapsibleContent };

export const Collapsible = Object.assign(CollapsibleRoot, {
  Root: CollapsibleRoot,
  Trigger: CollapsibleTrigger,
  Content: CollapsibleContent,
});

export default Collapsible;
