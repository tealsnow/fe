const std = @import("std");

pub const PluginSchema = struct {
    /// Id of plugin, must be unique, must be the same as the wasm filename (without the .wasm)
    id: []const u8,

    /// More user friendly name for plugin eg. 'My Awesome Plugin!'
    name: []const u8,

    /// Semver formatted version for plugin
    version: []const u8,

    /// User facing description of plugin
    description: []const u8,

    /// List of authors of plugin
    authors: []const []const u8,

    pub fn semanticVersion(schema: PluginSchema) !std.SemanticVersion {
        return .parse(schema.version);
    }
};
