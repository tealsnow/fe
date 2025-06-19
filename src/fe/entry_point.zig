const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"fe.entry_point");

const tracy = @import("tracy");

const cu = @import("cu");
const b = cu.builder;

const App = @import("app/App.zig");

const TestWindow = @import("app/TestWindow.zig");
const PanelWindow = @import("app/PanelWindow.zig");
const DebugWindow = @import("app/DebugWindow.zig");

pub fn entryPoint(root_allocator: Allocator) !void {
    // setup at the end before any defers are run
    //- tracy setup
    var deinit_trace: tracy.ZoneContext = undefined;
    defer deinit_trace.end();

    tracy.printAppInfo(App.APP_ID, .{});
    const init_trace = tracy.beginZone(@src(), .{ .name = "init" });

    log.info("starting fe", .{});

    if (tracy.isConnected()) log.debug("tracing enabled", .{});

    //- tracing allocator
    var tracing_allocator = tracy.TracingAllocator.init(root_allocator);
    const gpa = tracing_allocator.allocator();

    // @FIXME: keep getting error about improper instrumentation in tracy:
    //   a free event without a matching allocation
    //   likely that the in wasm allocator is not being traced i.e.
    //   an allocation in guest that is then freed in the host
    // //- plugin test
    // {
    //     const plugin_test_trace =
    //         tracy.beginZone(@src(), .{ .name = "plugin test" });
    //     defer plugin_test_trace.end();
    //
    //     log.info("setting up plugins", .{});
    //
    //     const host = try plugins.PluginHost.init(gpa);
    //     defer host.deinit(gpa);
    //
    //     const plugin = host.plugins[0];
    //     try plugins.doTest(plugin);
    // }

    //- app
    const app = try App.init(gpa);
    defer app.deinit();

    //- windows

    var test_window = try TestWindow.init(app);
    try app.addAppWindow(test_window.appWindow());

    var panel_window = try PanelWindow.init(app);
    try app.addAppWindow(panel_window.appWindow());

    var debug_window = try DebugWindow.init(app);
    try app.addAppWindow(debug_window.appWindow());

    //- main loop
    log.info("starting main loop", .{});
    init_trace.end();
    try app.run();

    //- tracy deinit trace
    deinit_trace = tracy.beginZone(@src(), .{ .name = "deinit" });
}
