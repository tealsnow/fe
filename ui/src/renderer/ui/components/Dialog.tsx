import type {
  Component,
  ComponentProps,
  JSX,
  JSXElement,
  ValidComponent,
} from "solid-js";
import { Show, splitProps } from "solid-js";

import * as DialogPrimitive from "@kobalte/core/dialog";
import type { PolymorphicProps } from "@kobalte/core/polymorphic";

import { cn } from "~/lib/cn";

import { Icon, icons } from "~/assets/icons";

import Button, { ButtonProps } from "~/ui/components/Button";
import * as Theme from "~/ui/Theme";

const DialogRoot = DialogPrimitive.Root;
const DialogTrigger = DialogPrimitive.Trigger;

const DialogPortal: Component<DialogPrimitive.DialogPortalProps> = (props) => {
  const [, rest] = splitProps(props, ["children"]);

  const themeCtx = Theme.useContext();

  return (
    <DialogPrimitive.Portal mount={themeCtx.rootElement()} {...rest}>
      <div class="fixed inset-0 z-50 flex items-start justify-center sm:items-center">
        {props.children}
      </div>
    </DialogPrimitive.Portal>
  );
};

type DialogOverlayProps<T extends ValidComponent = "div"> =
  DialogPrimitive.DialogOverlayProps<T> & { class?: string | undefined };

const DialogOverlay = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, DialogOverlayProps<T>>,
): JSXElement => {
  const [, rest] = splitProps(props as DialogOverlayProps, ["class"]);
  return (
    <DialogPrimitive.Overlay
      class={cn(
        "fixed inset-0 z-50 bg-theme-background/60",
        // "data-[expanded]:animate-in data-[closed]:animate-out data-[closed]:fade-out-0 data-[expanded]:fade-in-0",
        props.class,
      )}
      {...rest}
    />
  );
};

type DialogContentProps<T extends ValidComponent = "div"> =
  DialogPrimitive.DialogContentProps<T> & {
    class?: string | undefined;
    noCloseButton?: boolean;
    children?: JSX.Element;
  };

const DialogContent = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, DialogContentProps<T>>,
): JSXElement => {
  const [, rest] = splitProps(props as DialogContentProps, [
    "class",
    "noCloseButton",
    "children",
  ]);
  return (
    <DialogPortal>
      <DialogOverlay />
      <DialogPrimitive.Content
        class={cn(
          "fixed left-1/2 top-1/2 z-50 grid max-h-screen min-w-xs max-w-xl -translate-x-1/2 -translate-y-1/2 gap-2 overflow-y-auto border bg-theme-background p-2 shadow-lg",
          // "duration-200 data-[expanded]:animate-in data-[closed]:animate-out data-[closed]:fade-out-0 data-[expanded]:fade-in-0 data-[closed]:zoom-out-95 data-[expanded]:zoom-in-95 data-[closed]:slide-out-to-left-1/2 data-[closed]:slide-out-to-top-[48%] data-[expanded]:slide-in-from-left-1/2 data-[expanded]:slide-in-from-top-[48%] sm:rounded-lg",
          props.class,
        )}
        {...rest}
      >
        {props.children}
        <Show when={!props.noCloseButton}>
          <DialogCloseButton class="absolute right-1 top-1" />
        </Show>
      </DialogPrimitive.Content>
    </DialogPortal>
  );
};

const DialogHeader: Component<ComponentProps<"div">> = (props) => {
  const [, rest] = splitProps(props, ["class"]);
  return (
    <div
      class={cn(
        "flex flex-col space-y-1.5 text-center sm:text-left",
        props.class,
      )}
      {...rest}
    />
  );
};

const DialogFooter: Component<ComponentProps<"div">> = (props) => {
  const [, rest] = splitProps(props, ["class"]);
  return (
    <div
      class={cn(
        "flex flex-col-reverse sm:flex-row sm:justify-end sm:space-x-2",
        props.class,
      )}
      {...rest}
    />
  );
};

type DialogTitleProps<T extends ValidComponent = "h2"> =
  DialogPrimitive.DialogTitleProps<T> & {
    class?: string | undefined;
  };

const DialogTitle = <T extends ValidComponent = "h2">(
  props: PolymorphicProps<T, DialogTitleProps<T>>,
): JSXElement => {
  const [, rest] = splitProps(props as DialogTitleProps, ["class"]);
  return (
    <DialogPrimitive.Title
      class={cn(
        "text-md font-semibold leading-none tracking-tight mr-2",
        props.class,
      )}
      {...rest}
    />
  );
};

const DialogCloseButton: Component<ButtonProps> = (props) => {
  const [, rest] = splitProps(props, ["class"]);

  return (
    <DialogPrimitive.CloseButton
      as={Button}
      variant="icon"
      size="icon"
      class={cn("ml-auto opacity-70 border-0", props.class)}
      {...rest}
    >
      <Icon icon={icons["close"]} />
      <span class="sr-only">Close</span>
    </DialogPrimitive.CloseButton>
  );
};

type DialogDescriptionProps<T extends ValidComponent = "p"> =
  DialogPrimitive.DialogDescriptionProps<T> & {
    class?: string | undefined;
  };

const DialogDescription = <T extends ValidComponent = "p">(
  props: PolymorphicProps<T, DialogDescriptionProps<T>>,
): JSXElement => {
  const [, rest] = splitProps(props as DialogDescriptionProps, ["class"]);
  return (
    <DialogPrimitive.Description
      class={cn("text-sm text-muted-foreground", props.class)}
      {...rest}
    />
  );
};

export {
  DialogRoot,
  DialogTrigger,
  DialogContent,
  DialogHeader,
  DialogCloseButton,
  DialogFooter,
  DialogTitle,
  DialogDescription,
};

export const Dialog = Object.assign(DialogRoot, {
  Trigger: DialogTrigger,
  Content: DialogContent,
  Header: DialogHeader,
  CloseButton: DialogCloseButton,
  Footer: DialogFooter,
  Title: DialogTitle,
  Description: DialogDescription,
});
export default Dialog;
