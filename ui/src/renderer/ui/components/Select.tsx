import type { JSX, ValidComponent } from "solid-js";
import { splitProps } from "solid-js";

import type { PolymorphicProps } from "@kobalte/core/polymorphic";
import * as SelectPrimitive from "@kobalte/core/select";
import { cva } from "class-variance-authority";

import cn from "~/lib/cn";

import * as Theme from "~/ui/Theme";

export type SelectRootProps<T extends ValidComponent = "div"> =
  SelectPrimitive.SelectRootProps<T> & {
    class?: string | undefined;
    children?: JSX.Element;
  };

const SelectRoot = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SelectRootProps<T>>,
): JSX.Element => {
  const [local, others] = splitProps(props as SelectRootProps, [
    "class",
    "children",
  ]);
  return (
    <SelectPrimitive.Root class={cn(local.class)} gutter={2} {...others}>
      {local.children}
    </SelectPrimitive.Root>
  );
};

const SelectValue = SelectPrimitive.Value;
const SelectHiddenSelect = SelectPrimitive.HiddenSelect;

export type SelectTriggerProps<T extends ValidComponent = "button"> =
  SelectPrimitive.SelectTriggerProps<T> & {
    class?: string | undefined;
    children?: JSX.Element;
  };

const SelectTrigger = <T extends ValidComponent = "button">(
  props: PolymorphicProps<T, SelectTriggerProps<T>>,
): JSX.Element => {
  const [local, others] = splitProps(props as SelectTriggerProps, [
    "class",
    "children",
  ]);
  return (
    <SelectPrimitive.Trigger
      class={cn(
        // "flex h-6 w-full items-center justify-between rounded-md border border-input bg-transparent p-1 text-sm ring-offset-1 placeholder:text-theme-deemphasis focus:outline-none focus:ring-2 focus:ring-theme-border focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50",
        "flex h-6 w-full items-center justify-between rounded-md border border-input bg-transparent px-2 py-1 text-sm placeholder:text-theme-deemphasis disabled:cursor-not-allowed disabled:opacity-50 ring-0 outline-none",
        local.class,
      )}
      {...others}
    >
      {local.children}
      <SelectPrimitive.Icon
        as="svg"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
        class="size-4 opacity-50"
      >
        <path d="M8 9l4 -4l4 4" />
        <path d="M16 15l-4 4l-4 -4" />
      </SelectPrimitive.Icon>
    </SelectPrimitive.Trigger>
  );
};

export type SelectContentProps<T extends ValidComponent = "div"> =
  SelectPrimitive.SelectContentProps<T> & { class?: string | undefined };

const SelectContent = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SelectContentProps<T>>,
): JSX.Element => {
  const [local, others] = splitProps(props as SelectContentProps, ["class"]);

  const themeCtx = Theme.useContext();

  return (
    <SelectPrimitive.Portal mount={themeCtx.rootElement()}>
      <SelectPrimitive.Content
        class={cn(
          "relative z-50 min-w-32 overflow-hidden rounded-md border bg-theme-background text-theme-text shadow-md transition-opacity animate-in fade-in-80 duration-200",
          local.class,
        )}
        {...others}
      >
        <SelectPrimitive.Listbox class="m-0 p-1" />
      </SelectPrimitive.Content>
    </SelectPrimitive.Portal>
  );
};

export type SelectItemProps<T extends ValidComponent = "li"> =
  SelectPrimitive.SelectItemProps<T> & {
    class?: string | undefined;
    children?: JSX.Element;
  };

const SelectItem = <T extends ValidComponent = "li">(
  props: PolymorphicProps<T, SelectItemProps<T>>,
): JSX.Element => {
  const [local, others] = splitProps(props as SelectItemProps, [
    "class",
    "children",
  ]);
  return (
    <SelectPrimitive.Item
      class={cn(
        "relative mt-0 flex w-full cursor-default select-none items-center rounded-sm py-1 pl-1 pr-8 text-sm outline-none focus:bg-theme-border focus:text-theme-deemphasis data-[disabled]:pointer-events-none data-[disabled]:opacity-50",
        local.class,
      )}
      {...others}
    >
      <SelectPrimitive.ItemIndicator class="absolute right-2 flex size-3.5 items-center justify-center">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="size-4"
        >
          <path stroke="none" d="M0 0h24v24H0z" fill="none" />
          <path d="M5 12l5 5l10 -10" />
        </svg>
      </SelectPrimitive.ItemIndicator>
      <SelectPrimitive.ItemLabel>{local.children}</SelectPrimitive.ItemLabel>
    </SelectPrimitive.Item>
  );
};

export const labelVariants = cva(
  "text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70",
  {
    variants: {
      variant: {
        label: "data-[invalid]:text-destructive",
        description: "font-normal text-muted-foreground",
        error: "text-xs text-destructive",
      },
    },
    defaultVariants: {
      variant: "label",
    },
  },
);

export type SelectLabelProps<T extends ValidComponent = "label"> =
  SelectPrimitive.SelectLabelProps<T> & {
    class?: string | undefined;
  };

const SelectLabel = <T extends ValidComponent = "label">(
  props: PolymorphicProps<T, SelectLabelProps<T>>,
): JSX.Element => {
  const [local, others] = splitProps(props as SelectLabelProps, ["class"]);
  return (
    <SelectPrimitive.Label
      class={cn(labelVariants(), local.class)}
      {...others}
    />
  );
};

export type SelectDescriptionProps<T extends ValidComponent = "div"> =
  SelectPrimitive.SelectDescriptionProps<T> & {
    class?: string | undefined;
  };

const SelectDescription = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SelectDescriptionProps<T>>,
): JSX.Element => {
  const [local, others] = splitProps(props as SelectDescriptionProps, [
    "class",
  ]);
  return (
    <SelectPrimitive.Description
      class={cn(labelVariants({ variant: "description" }), local.class)}
      {...others}
    />
  );
};

export type SelectErrorMessageProps<T extends ValidComponent = "div"> =
  SelectPrimitive.SelectErrorMessageProps<T> & {
    class?: string | undefined;
  };

const SelectErrorMessage = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SelectErrorMessageProps<T>>,
): JSX.Element => {
  const [local, others] = splitProps(props as SelectErrorMessageProps, [
    "class",
  ]);
  return (
    <SelectPrimitive.ErrorMessage
      class={cn(labelVariants({ variant: "error" }), local.class)}
      {...others}
    />
  );
};

export {
  SelectRoot,
  SelectValue,
  SelectHiddenSelect,
  SelectTrigger,
  SelectContent,
  SelectItem,
  SelectLabel,
  SelectDescription,
  SelectErrorMessage,
};

export const Select = Object.assign(SelectRoot, {
  Value: SelectValue,
  HiddenSelect: SelectHiddenSelect,
  Trigger: SelectTrigger,
  Content: SelectContent,
  Item: SelectItem,
  Label: SelectLabel,
  Description: SelectDescription,
  ErrorMessage: SelectErrorMessage,
});

export default Select;
