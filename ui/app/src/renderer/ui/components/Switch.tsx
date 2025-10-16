import type { JSX, ValidComponent } from "solid-js";
import { splitProps } from "solid-js";

import type { PolymorphicProps } from "@kobalte/core";
import * as SwitchPrimitive from "@kobalte/core/switch";

import cn from "~/lib/cn";

// const SwitchRoot = SwitchPrimitive.Root;
const SwitchDescription = SwitchPrimitive.Description;
const SwitchErrorMessage = SwitchPrimitive.ErrorMessage;

export type SwitchRootProps = SwitchPrimitive.SwitchRootProps & {
  class?: string | undefined;
  children?: JSX.Element;
};

const SwitchRoot = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SwitchRootProps>,
): JSX.Element => {
  const [local, others] = splitProps(props as SwitchRootProps, [
    "class",
    "children",
  ]);

  return (
    <SwitchPrimitive.Root
      class={cn("flex flex-row items-center gap-1", local.class)}
      {...others}
    >
      {local.children}
    </SwitchPrimitive.Root>
  );
};

export type SwitchControlProps = SwitchPrimitive.SwitchControlProps & {
  class?: string | undefined;
  children?: JSX.Element;
};

const SwitchControl = <T extends ValidComponent = "input">(
  props: PolymorphicProps<T, SwitchControlProps>,
): JSX.Element => {
  const [local, others] = splitProps(props as SwitchControlProps, [
    "class",
    "children",
  ]);
  return (
    <>
      <SwitchPrimitive.Input
        class={cn(
          // "[&:focus-visible+div]:outline-none [&:focus-visible+div]:ring-2 [&:focus-visible+div]:ring-ring [&:focus-visible+div]:ring-offset-2 [&:focus-visible+div]:ring-offset-background",
          "[&:focus-visible+div]:outline-none",
          local.class,
        )}
      />
      <SwitchPrimitive.Control
        class={cn(
          "inline-flex h-4.5 w-8 shrink-0 cursor-pointer items-center rounded-full border-1 bg-theme-background transition-[color,background-color,box-shadow] data-[disabled]:cursor-not-allowed data-[checked]:bg-theme-text data-[disabled]:opacity-50",
          local.class,
        )}
        {...others}
      >
        {local.children}
      </SwitchPrimitive.Control>
    </>
  );
};

export type SwitchThumbProps = SwitchPrimitive.SwitchThumbProps & {
  class?: string | undefined;
};

const SwitchThumb = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SwitchThumbProps>,
): JSX.Element => {
  const [local, others] = splitProps(props as SwitchThumbProps, ["class"]);
  return (
    <SwitchPrimitive.Thumb
      class={cn(
        "pointer-events-none block size-3.5 ml-px translate-x-0 rounded-full bg-theme-border shadow-lg ring-0 transition-transform data-[checked]:translate-x-3.5 duration-100",
        local.class,
      )}
      {...others}
    />
  );
};

export type SwitchLabelProps = SwitchPrimitive.SwitchLabelProps & {
  class?: string | undefined;
};

const SwitchLabel = <T extends ValidComponent = "label">(
  props: PolymorphicProps<T, SwitchLabelProps>,
): JSX.Element => {
  const [local, others] = splitProps(props as SwitchLabelProps, ["class"]);
  return (
    <SwitchPrimitive.Label
      class={cn(
        "text-sm font-medium leading-none data-[disabled]:cursor-not-allowed data-[disabled]:opacity-70",
        local.class,
      )}
      {...others}
    />
  );
};

export {
  SwitchRoot,
  SwitchControl,
  SwitchThumb,
  SwitchLabel,
  SwitchDescription,
  SwitchErrorMessage,
};

export const Switch = Object.assign(SwitchRoot, {
  Control: SwitchControl,
  Thumb: SwitchThumb,
  Label: SwitchLabel,
  Description: SwitchDescription,
  ErrorMessage: SwitchErrorMessage,
});

export default Switch;
