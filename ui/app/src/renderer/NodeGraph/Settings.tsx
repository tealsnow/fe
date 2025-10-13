import { Accessor, VoidComponent } from "solid-js";
import { SetStoreFunction } from "solid-js/store";

import cn from "~/lib/cn";
import UpdateFn from "~/lib/UpdateFn";

import Icon from "~/ui/components/Icon";
import Switch from "~/ui/components/Switch";
import Select from "~/ui/components/Select";
import Collapsible from "~/ui/components/Collapsible";
import Label from "~/ui/components/Label";

import {
  Config,
  ConfigDefault,
  SnapKind,
  SnapConfig,
  GridStyle,
  GridStyleNames,
} from "./Config";

// @TODO: reset buttons
export const Settings: VoidComponent<{
  class?: string;
  config: Config;
  setConfig: SetStoreFunction<Config>;
}> = (props) => {
  const SnapConfig: VoidComponent<{
    label: string;
    snapConfig: Accessor<SnapConfig>;
    setSnapConfig: UpdateFn<SnapConfig>;
  }> = (props) => {
    const KindSelect: VoidComponent<{
      label: string;
      kind: () => SnapKind;
      setKind: (kind: SnapKind) => void;
    }> = (props) => {
      // intentional
      // eslint-disable-next-line solid/reactivity
      const initialDefault = props.kind();

      return (
        <Select<SnapKind>
          class="flex items-center gap-1 w-full"
          value={props.kind()}
          onChange={(s) => props.setKind(s ?? props.kind())}
          options={[...SnapKind]}
          defaultValue={initialDefault}
          itemComponent={(props) => (
            <Select.Item item={props.item}>{props.item.textValue}</Select.Item>
          )}
        >
          <Select.Label class="mr-auto">{props.label}</Select.Label>

          <Select.Trigger class="w-40">
            <Select.Value<GridStyle>>
              {(state) => state.selectedOption()}
            </Select.Value>
          </Select.Trigger>
          <Select.Content />
        </Select>
      );
    };

    return (
      <Collapsible>
        <Collapsible.Trigger class="div group flex flex-row gap-2 my-1">
          <Icon
            icon="ChevronRight"
            class="size-3 fill-none transition-transform duration-100 group-data-[expanded]:rotate-90"
          />
          <Label>{props.label}</Label>
        </Collapsible.Trigger>
        <Collapsible.Content class="mt-1 ml-8 flex flex-col gap-1">
          <KindSelect
            label="default"
            kind={() => props.snapConfig().default}
            setKind={(kind) =>
              props.setSnapConfig((c) => ({ ...c, default: kind }))
            }
          />
          <KindSelect
            label="shift"
            kind={() => props.snapConfig().shift}
            setKind={(kind) =>
              props.setSnapConfig((c) => ({ ...c, shift: kind }))
            }
          />
          <KindSelect
            label="ctrl"
            kind={() => props.snapConfig().ctrl}
            setKind={(kind) =>
              props.setSnapConfig((c) => ({ ...c, ctrl: kind }))
            }
          />
          <KindSelect
            label="ctrl+shift"
            kind={() => props.snapConfig().ctrlShift}
            setKind={(kind) =>
              props.setSnapConfig((c) => ({ ...c, ctrlShift: kind }))
            }
          />
        </Collapsible.Content>
      </Collapsible>
    );
  };

  return (
    <div class={cn("flex flex-col gap-1", props.class)}>
      <h2 class="text-lg underline underline-offset-2">Settings</h2>

      <Switch
        class="flex items-center gap-1 w-full"
        checked={props.config.snapNodeSizesToGrid}
        onChange={() => props.setConfig("snapNodeSizesToGrid", (b) => !b)}
      >
        <Switch.Label class="mr-auto">Snap node sizes to grid</Switch.Label>

        <Switch.Control>
          <Switch.Thumb />
        </Switch.Control>
      </Switch>

      <Select<GridStyle>
        class="flex items-center gap-1 w-full"
        value={props.config.gridStyle}
        onChange={(s) =>
          props.setConfig("gridStyle", s ?? ConfigDefault.gridStyle)
        }
        options={[...GridStyle]}
        defaultValue={ConfigDefault.gridStyle}
        itemComponent={(props) => (
          <Select.Item item={props.item}>
            {GridStyleNames[props.item.textValue]}
          </Select.Item>
        )}
      >
        <Select.Label class="mr-auto">Grid style</Select.Label>

        <Select.Trigger class="w-40">
          <Select.Value<GridStyle>>
            {(state) => GridStyleNames[state.selectedOption()]}
          </Select.Value>
        </Select.Trigger>
        <Select.Content />
      </Select>

      <SnapConfig
        label="Pan snap settings"
        snapConfig={() => props.config.snapping.canvas}
        setSnapConfig={(fn) => props.setConfig("snapping", "canvas", fn)}
      />

      <SnapConfig
        label="Node snap settings"
        snapConfig={() => props.config.snapping.nodes}
        setSnapConfig={(fn) => props.setConfig("snapping", "nodes", fn)}
      />
    </div>
  );
};

export default Settings;
