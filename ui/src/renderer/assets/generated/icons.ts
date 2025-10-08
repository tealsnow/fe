export const IconKind = ["add", "adwaita_window_close", "adwaita_window_maximize", "adwaita_window_minimize", "adwaita_window_restore", "bell", "chevron_right", "close", "dnd_split_append", "dnd_split_insert", "dnd_tabs_middle", "dnd_tabs_side", "fe", "fe_transparent", "key_ctrl_down", "key_ctrl_up", "key_shift_down", "key_shift_up", "sidebar_indicator_disabled", "sidebar_indicator_enabled", "window_maximize", "window_minimize", "window_restore"] as const;

export type IconKind = (typeof IconKind)[number];
