const std = @import("std");

pub const EntryPoint = enum {
    sdl,
    glfw,
    wayland,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const entry_point =
        b.option(
            EntryPoint,
            "entry_point",
            "specify entry point to use",
        ) orelse .wayland;

    const profile =
        b.option(
            bool,
            "profile",
            "Enable profiling with tracy (always uses llvm)",
        ) orelse false;

    const use_llvm =
        b.option(
            bool,
            "use_llvm",
            "switch to use llvm or not (defaults to false for debug and true for release)",
        ) orelse
        if (optimize == .Debug) profile else true;

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

    const poll_event_loop =
        b.option(
            bool,
            "poll_event_loop",
            "Whether to poll for events or have a timeout (default: false)",
        ) orelse false;

    const fmt_step = b.addFmt(.{
        .check = true,
        .paths = &.{"src/"},
    });
    b.getInstallStep().dependOn(&fmt_step.step);

    const tracy = b.dependency("tracy", .{
        .target = target,
        .optimize = optimize,
        .tracy_enable = profile,
        .shared = false,
    });

    const glfw = b.dependency("glfw", .{
        .target = target,
        .optimize = optimize,
    });

    const wgpu = b.dependency("wgpu", .{
        .target = target,
        .optimize = optimize,
    });

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
            // .use_lld = false,
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

        mod.addImport("tracy", tracy.module("tracy"));
        if (profile) {
            mod.linkLibrary(tracy.artifact("tracy"));
            mod.link_libcpp = true;
        }

        const cu = b.addLibrary(.{
            .name = "cu",
            .root_module = mod,

            .use_llvm = use_llvm,
            .use_lld = use_llvm,
            // .use_lld = false,
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

        const fe = b.addExecutable(.{
            .name = "fe",
            .root_module = mod,

            .use_llvm = use_llvm,
            .use_lld = use_llvm,
            // .use_lld = false,
        });
        b.installArtifact(fe);

        mod.link_libc = true;
        mod.linkSystemLibrary("fontconfig", .{ .needed = true });
        mod.linkSystemLibrary("wasmtime", .{ .needed = true });

        switch (entry_point) {
            .sdl => {
                mod.addImport("sdl3", sdl3.root_module);
                mod.linkLibrary(sdl3);
            },
            .glfw => {
                mod.addImport("glfw", glfw.module("glfw"));
                mod.linkLibrary(glfw.artifact("glfw"));

                mod.addImport("wgpu", wgpu.module("wgpu"));
            },
            .wayland => {
                mod.linkSystemLibrary("wayland-client", .{ .needed = true });

                const xdg_shell_share_path = "wayland-protocols/stable/xdg-shell/xdg-shell.xml";
                const xdg_shell_generated_root = "src/fe/wayland/";
                const xdg_shell_generated_code_path = "xdg-shell-protocal.c";
                const xdg_shell_generated_header_path = "xdg-shell-client-protocal.h";

                const xdg_shell_path = findPathInXdgDataDirs(b, xdg_shell_share_path).?;
                const get_xdg_shell_code = b.addSystemCommand(&.{
                    "wayland-scanner",
                    "private-code",
                    xdg_shell_path,
                    xdg_shell_generated_root ++ xdg_shell_generated_code_path,
                });
                const get_xdg_shell_header = b.addSystemCommand(&.{
                    "wayland-scanner",
                    "client-header",
                    xdg_shell_path,
                    xdg_shell_generated_root ++ xdg_shell_generated_header_path,
                });

                fe.step.dependOn(&get_xdg_shell_code.step);
                fe.step.dependOn(&get_xdg_shell_header.step);

                mod.addCSourceFiles(.{
                    .root = b.path(xdg_shell_generated_root),
                    .files = &.{xdg_shell_generated_code_path},
                });
                mod.addIncludePath(b.path(xdg_shell_generated_root));
            },
        }

        mod.addImport("cu", cu.root_module);
        mod.linkLibrary(cu);

        mod.addImport("tracy", tracy.module("tracy"));
        if (profile) {
            mod.linkLibrary(tracy.artifact("tracy"));
            mod.link_libcpp = true;
        }

        const plugin_schema = getPluginSchema(b);
        mod.addImport("plugin-schema", plugin_schema);

        const options = b.addOptions();
        options.addOption(std.log.Level, "log_level", log_level);
        options.addOption(bool, "poll_event_loop", poll_event_loop);
        options.addOption(EntryPoint, "entry_point", entry_point);
        mod.addOptions("build_options", options);

        break :fe fe;
    };

    // test plugin
    {
        const mod = createPluginModule(b, .{
            .root_source_file = b.path("src/plugins/test/test.zig"),
            .optimize = optimize,
            .schema_path = b.path("src/plugins/test/plugin.zon"),
            .export_symbol_names = &.{
                // "foo_bar",
                "helloWorld",
                "add",
                "addi64",
                "runCallback",
                "takeFooType",
                "giveString",
                "returnFunc",
                "runFunc",
            },
        });

        const bin = addPlugin(b, .{
            .name = "test-plugin",
            .root_module = mod,
        });

        const install = bin.installPlugin(b, "plugins/test");

        fe.step.dependOn(&install.step);
    }

    // run
    {
        const run_cmd = b.addRunArtifact(fe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        if (profile) {
            // @TODO: Figure out a portable alternative to setsid
            // @NOTE: setsid used since `addSystemCommand` is blocking
            //  without it, the build system would launch tracy then wait for
            //  it to close before running the app
            const tracy_cmd = b.addSystemCommand(&.{ "setsid", "-f", "tracy", "-a", "localhost" });
            run_cmd.step.dependOn(&tracy_cmd.step);
        }
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

/// This should mostly mirror `std.Build.Module.CreateOptions`
/// and thus its documentation applies
pub const CreatePluginModuleOptions = struct {
    root_source_file: ?std.Build.LazyPath = null,

    imports: []const std.Build.Module.Import = &.{},

    // we intentionally leave out target, as it is already defined for a plugin
    // regardless of platform
    optimize: ?std.builtin.OptimizeMode = null,

    // Not sure if this is needed or even relavant for wasm
    // link_libc: ?bool = null,
    // link_libcpp: ?bool = null,

    // multithreading support is not implemented for wasm as of yet
    // single_threaded: ?bool = null,

    strip: ?bool = null,
    unwind_tables: ?std.builtin.UnwindTables = null,

    // we only support 32-bit wasm for now
    // not even sure if wasm uses Dwarf in the first place
    // dwarf_format: ?std.dwarf.Format = null,

    code_model: std.builtin.CodeModel = .default,

    // @TODO: Figure out of these are even used in wasm
    stack_protector: ?bool = null,
    stack_check: ?bool = null,
    // sanitize_c: ?bool = null, // we don't link libc for now
    // sanitize_thread: ?bool = null, // no threading yet
    fuzz: ?bool = null,
    valgrind: ?bool = null,
    pic: ?bool = null,
    red_zone: ?bool = null,
    omit_frame_pointer: ?bool = null,

    error_tracing: ?bool = null,

    // Not found in `std.Build.Module.CreateOptions`:

    schema_path: std.Build.LazyPath,
    export_symbol_names: []const []const u8 = &.{},
};

pub const PluginModule = struct {
    module: *std.Build.Module,
    schema_path: std.Build.LazyPath,
};

pub fn createPluginModule(b: *std.Build, options: CreatePluginModuleOptions) *PluginModule {
    const wasm_target = b.resolveTargetQuery(.{
        // unfortunatly as of zig 0.14 support for wasm64/memory64 is not yet implemented:
        // https://ziglang.org/download/0.14.0/release-notes.html#Support-Table#:~:text=wasm64-wasi
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
        .cpu_features_add = std.Target.wasm.featureSet(&.{
            // wasmtime support table:
            // https://docs.wasmtime.dev/stability-wasm-proposals.html#feature-requirements

            // Supported by wasmtime:
            .bulk_memory,
            .extended_const,
            // .multimemory,
            .multivalue, // https://github.com/ziglang/zig/issues/16639
            .mutable_globals,
            .nontrapping_fptoint,
            .reference_types,
            .sign_ext,
            .relaxed_simd,
            .simd128,
            .tail_call, // breaks wasm2wat
            // .atomics, // probably part of threads support, which zig does not have for wasm

            // Unsupprted by wasmtime:
            // .exception_handling,
            // .half_precision,
            //
            // Unknown if supported by wasmtime:
            // .nontrapping_bulk_memory_len0,

            // Missing (from zig stdlib):
            //   supported by wasmtime:
            //     component-model https://github.com/ziglang/zig/issues/16639
            //     threads
            //     memory64
            //
            //   unsupported by wasmtime:
            //     branch-hinting
            //     flexible-vectors
            //     memory-control
            //     stack-switching
            //     shared-everything-threads
        }),
    });

    const mod = b.createModule(.{
        .root_source_file = options.root_source_file,
        .imports = options.imports,
        .target = wasm_target,
        .optimize = options.optimize,
        .strip = options.strip,
        .unwind_tables = options.unwind_tables,
        .code_model = options.code_model,
        .stack_protector = options.stack_protector,
        .stack_check = options.stack_check,
        .fuzz = options.fuzz,
        .valgrind = options.valgrind,
        .pic = options.pic,
        .red_zone = options.red_zone,
        .omit_frame_pointer = options.omit_frame_pointer,
        .error_tracing = options.error_tracing,
    });

    mod.export_symbol_names = options.export_symbol_names;

    const pmod = b.allocator.create(PluginModule) catch @panic("OOM");
    pmod.* = .{
        .module = mod,
        .schema_path = options.schema_path,
    };

    return pmod;
}

/// This should mostly mirror `std.Build.ExecutableOptions`
/// and thus its documentation applies
pub const PluginOptions = struct {
    name: []const u8,
    version: ?std.SemanticVersion = null,
    max_rss: usize = 0,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    root_module: *PluginModule,
};

pub const PluginCompile = struct {
    bin: *std.Build.Step.Compile,
    schema_install: *std.Build.Step.InstallFile,

    pub fn installPlugin(compile: *PluginCompile, b: *std.Build, rel_out_dir: []const u8) *std.Build.Step.InstallArtifact {
        const schema_path = b.pathJoin(&.{ rel_out_dir, "plugin.zon" });
        compile.schema_install.dest_rel_path = schema_path;

        return b.addInstallArtifact(compile.bin, .{
            .dest_dir = .{ .override = .{ .custom = rel_out_dir } },
        });
    }
};

pub fn addPlugin(b: *std.Build, options: PluginOptions) *PluginCompile {
    const bin = b.addExecutable(.{
        .name = options.name,
        .version = options.version,
        .max_rss = options.max_rss,
        .use_llvm = options.use_lld,
        .use_lld = options.use_lld,
        .root_module = options.root_module.module,
    });

    const plugin_lib = getPluginLib(b);
    bin.root_module.addImport("plugin-lib", plugin_lib);

    bin.rdynamic = true;
    bin.entry = .disabled;

    bin.import_symbols = true;
    bin.export_table = true;

    bin.import_memory = true;
    bin.export_memory = true;

    // bin.shared_memory = true; // not supported until we have wasm thread support

    // @NOTE:
    //  Might be worth having the schema be described directly in build.zig
    //
    //  Also might be a good idea to add a list of exports to it.
    //  This could be usefull - such as giving the host a name of an exported
    //  function (that the host has already grabbed and stored) to be used
    //  for callbacks and such.
    //
    //  Also since we're talking about schema files here:
    //  I might as well add that at some point an inter-plugin dependancy system
    //  would be a good idea
    const schema_install = b.addInstallFile(options.root_module.schema_path, "/");
    bin.step.dependOn(&schema_install.step);

    const compile = b.allocator.create(PluginCompile) catch @panic("oom");
    compile.* = .{
        .bin = bin,
        .schema_install = schema_install,
    };

    return compile;
}

pub fn getPluginLib(b: *std.Build) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/plugin-lib/lib.zig"),
    });

    mod.export_symbol_names = &.{
        "Allocator_alloc",
        "Allocator_resize",
        "Allocator_remap",
        "Allocator_free",
    };

    const plugin_schema = getPluginSchema(b);
    mod.addImport("plugin-schema", plugin_schema);

    return mod;
}

pub fn getPluginSchema(b: *std.Build) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/plugin-schema/schema.zig"),
    });
}

fn findPathInXdgDataDirs(b: *std.Build, path: []const u8) ?[]const u8 {
    const env = std.process.getEnvMap(b.allocator) catch @panic("oom");
    // defer env.deinit(); // no need to wait time deinit thing

    const data_dirs = env.get("XDG_DATA_DIRS") orelse {
        // if no XDG_DATA_DIRS env we just check the default path
        const dir = std.fs.openDirAbsolute("/usr/share/", .{}) catch return null;
        dir.access(path, .{}) catch return null;
        return b.pathJoin(&.{ "/usr/share/", path });
    };

    var iter = std.mem.splitScalar(u8, data_dirs, ':');
    while (iter.next()) |dir_path| {
        // open dir - if not try next
        const dir = std.fs.openDirAbsolute(dir_path, .{}) catch continue;
        // check if exists and we have access - otherwise try next
        dir.access(path, .{}) catch continue;

        return b.pathJoin(&.{ dir_path, path });
    }

    return null;
}
