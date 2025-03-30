const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_llvm = b.option(
        bool,
        "use_llvm",
        "switch to use llvm or not (defaults to false on debug builds true for release builds)",
    ) orelse if (optimize == .Debug) false else true;

    const log_level: std.log.Level =
        b.option(
            std.log.Level,
            "log_level",
            "What log level to use regardless of the build mode",
        ) orelse switch (optimize) {
            .Debug => .debug,
            .ReleaseSafe => .info,
            .ReleaseFast, .ReleaseSmall => .warn,
        };

    const fmt_step = b.addFmt(.{
        .check = true,
        .paths = &.{"src/"},
    });
    b.getInstallStep().dependOn(&fmt_step.step);

    const plugin_schema = schema: {
        const mod = b.createModule(.{
            .root_source_file = b.path("src/plugin-schema/schema.zig"),
        });
        break :schema mod;
    };

    const sdl3 = sdl3: {
        const mod = b.createModule(.{
            .root_source_file = b.path("src/sdl3/sdl3.zig"),
            .target = target,
            .optimize = optimize,
        });
        mod.link_libc = true;
        mod.linkSystemLibrary("sdl3", .{ .needed = true });
        mod.linkSystemLibrary("sdl3-ttf", .{ .needed = true });

        const sdl3 = b.addLibrary(.{
            .name = "sdl3",
            .root_module = mod,

            .use_llvm = use_llvm,
            .use_lld = use_llvm,
        });
        b.installArtifact(sdl3);

        break :sdl3 sdl3;
    };

    const cu = cu: {
        const mod = b.createModule(.{
            .root_source_file = b.path("src/cu/cu.zig"),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("sdl3", sdl3.root_module);
        mod.linkLibrary(sdl3);

        const cu = b.addLibrary(.{
            .name = "cu",
            .root_module = mod,

            .use_llvm = use_llvm,
            .use_lld = use_llvm,
        });
        b.installArtifact(cu);

        break :cu cu;
    };

    const fe = fe: {
        const mod = b.createModule(.{
            .root_source_file = b.path("src/fe/fe.zig"),
            .target = target,
            .optimize = optimize,
        });

        mod.link_libc = true;
        mod.linkSystemLibrary("fontconfig", .{ .needed = true });
        mod.linkSystemLibrary("wasmtime", .{ .needed = true });

        mod.addImport("sdl3", sdl3.root_module);
        mod.linkLibrary(sdl3);

        mod.addImport("cu", cu.root_module);
        mod.linkLibrary(cu);

        mod.addImport("plugin-schema", plugin_schema);

        const options = b.addOptions();
        options.addOption(std.log.Level, "log_level", log_level);
        mod.addOptions("build_options", options);

        const fe = b.addExecutable(.{
            .name = "fe",
            .root_module = mod,

            .use_llvm = use_llvm,
            .use_lld = use_llvm,
        });
        b.installArtifact(fe);

        break :fe fe;
    };

    const plugin_lib = lib: {
        const mod = b.createModule(.{
            .root_source_file = b.path("src/plugin-lib/lib.zig"),
        });
        mod.addImport("plugin-schema", plugin_schema);

        mod.export_symbol_names = &.{
            "Allocator_alloc",
            "Allocator_resize",
            "Allocator_remap",
            "Allocator_free",
        };

        break :lib mod;
    };

    // test plugin
    {
        const wasm_target = b.resolveTargetQuery(.{
            // unfortunatly wasm64/memory64 support for wasi is not yet implemented
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
        });

        const mod = b.createModule(.{
            .root_source_file = b.path("src/plugins/test/test.zig"),
            .target = wasm_target,
            .optimize = optimize,
        });
        mod.addImport("plugin-lib", plugin_lib);
        mod.export_symbol_names = &.{
            // "foo_bar",
            "helloWorld",
            "add",
            "addi64",
            "runCallback",
            "takeFooType",
            "giveString",
        };

        const bin = b.addExecutable(.{
            .name = "test-plugin",
            .root_module = mod,

            .use_llvm = use_llvm,
            .use_lld = use_llvm,
        });
        bin.rdynamic = true;
        bin.entry = .disabled;
        const wasm_install = b.addInstallArtifact(bin, .{
            .dest_dir = .{ .override = .{ .custom = "plugins/test/" } },
        });

        const schema_install = b.addInstallFile(b.path("src/plugins/test/plugin.zon"), "plugins/test/plugin.zon");
        wasm_install.step.dependOn(&schema_install.step);

        fe.step.dependOn(&wasm_install.step);
    }

    // run
    {
        const run_cmd = b.addRunArtifact(fe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    // check
    {
        const check_step = b.step("check", "check");
        check_step.dependOn(&fe.step);
    }

    // test
    {
        const exe_unit_tests = b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_exe_unit_tests.step);
    }
}
