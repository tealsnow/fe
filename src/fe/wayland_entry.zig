const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"fe[wl]");

const cu = @import("cu");

const tracy = @import("tracy");
const plugins = @import("plugins.zig");

const AppState = @import("app/State.zig");
const Window = AppState.Window;

const TestWindow = @import("app/TestWindow.zig");
const PanelWindow = @import("app/PanelWindow.zig");

pub fn entryPoint(gpa: Allocator) !void {
    // setup at the end before any defers are run
    var deinit_trace: tracy.ZoneContext = undefined;
    defer deinit_trace.end();

    tracy.printAppInfo(AppState.APP_ID, .{});
    const init_trace = tracy.beginZone(@src(), .{ .name = "init" });

    //- plugin test
    {
        const plugin_test_trace =
            tracy.beginZone(@src(), .{ .name = "plugin test" });
        defer plugin_test_trace.end();

        log.info("setting up plugins", .{});

        const host = try plugins.PluginHost.init(gpa);
        defer host.deinit(gpa);

        const plugin = host.plugins[0];
        try plugins.doTest(plugin);
    }

    //- arena

    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    var tracing_arena_alloc =
        tracy.TracingAllocator.initNamed("arena", arena_alloc.allocator());
    defer tracing_arena_alloc.discard();
    const arena = tracing_arena_alloc.allocator();

    //- state

    var state = try AppState.init(gpa, arena);
    defer state.deinit();

    //- windows

    var test_window_state = TestWindow{ .app = &state };
    _ = try state.newWindow(.{
        .title = "Test",
        .initial_size = .size(1024, 576),
        .interface = test_window_state.windowInterface(),
    });

    const panel_window_state = try PanelWindow.init(&state);
    _ = try state.newWindow(.{
        .title = "Panels",
        .initial_size = .size(800, 600),
        .interface = panel_window_state.windowInterface(),
    });

    //- main loop

    log.info("starting main loop", .{});

    init_trace.end();

    while (state.running) {
        tracy.frameMark();

        try state.runUpdate();

        _ = arena_alloc.reset(.retain_capacity);
        tracing_arena_alloc.discard();
    }

    deinit_trace = tracy.beginZone(@src(), .{ .name = "deinit" });
}
