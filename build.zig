const std = @import("std");

const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //- options

    const no_bin =
        b.option(
            bool,
            "no_bin",
            "Do not emit binaries (default: false)",
        ) orelse false;

    const valgrind =
        b.option(
            bool,
            "valgrind",
            "Indicate that app will be run with valgrind (default: false)",
        ) orelse false;

    const profile =
        b.option(
            bool,
            "profile",
            "Enable profiling with tracy (default: false)",
        ) orelse false;

    const use_llvm =
        b.option(
            bool,
            "use_llvm",
            "build using the llvm backend (default: true)",
        ) orelse true;

    if (profile and !use_llvm)
        std.log.warn(
            "profiling without using llvm backend might not work corretly",
            .{},
        );

    const log_level: std.log.Level =
        b.option(
            std.log.Level,
            "log_level",
            "What log level to use regardless of the build mode " ++
                "(defaults: Debug -> debug, ReleaseSafe -> info, ReleaseFast, ReleaseSmall -> warn)",
        ) orelse switch (optimize) {
            .Debug => .debug,
            .ReleaseSafe => .info,
            .ReleaseFast, .ReleaseSmall => .warn,
        };

    //- fmt

    const fmt_step = b.addFmt(.{
        .check = true,
        .paths = &.{"src/"},
    });
    b.getInstallStep().dependOn(&fmt_step.step);

    //- tracy

    const tracy = b.lazyDependency("tracy", .{
        .target = target,
        .optimize = optimize,
        .tracy_enable = profile,
        .shared = false,
    });

    //- pretty printing

    const pretty_print = b.lazyDependency("pretty", .{
        .target = target,
        .optimize = optimize,
    });

    //- cu

    const cu_mod = b.createModule(.{
        .root_source_file = b.path("src/cu/cu.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (tracy) |m| {
        cu_mod.addImport("tracy", m.module("tracy"));
        if (profile) {
            cu_mod.linkLibrary(m.artifact("tracy"));
            cu_mod.link_libcpp = true;
        }
    }

    const cu_lib = b.addLibrary(.{
        .name = "cu",
        .root_module = cu_mod,

        .use_llvm = use_llvm,
        .use_lld = use_llvm,
        // .use_lld = false,
    });
    if (no_bin)
        b.getInstallStep().dependOn(&cu_lib.step)
    else
        b.installArtifact(cu_lib);

    //- fe

    const fe_mod = b.createModule(.{
        .root_source_file = b.path("src/fe/fe.zig"),
        .target = target,
        .optimize = optimize,
    });

    const fe_exe = b.addExecutable(.{
        .name = "fe",
        .root_module = fe_mod,

        .use_llvm = use_llvm,
        .use_lld = use_llvm,
        // .use_lld = false,
    });
    if (no_bin)
        b.getInstallStep().dependOn(&fe_exe.step)
    else
        b.installArtifact(fe_exe);

    fe_mod.link_libc = true;
    fe_mod.linkSystemLibrary("wasmtime", .{ .needed = true });

    //- sdl
    if (false) {
        if (b.lazyDependency("sdl3", .{
            .target = target,
            .optimize = optimize,
        })) |sdl3| {
            fe_mod.addImport("sdl3", sdl3.module("sdl3"));

            fe_mod.linkSystemLibrary("sdl3", .{ .needed = true });
            fe_mod.linkSystemLibrary("sdl3-ttf", .{ .needed = true });
        }
    }

    //- linux wayland
    {
        const xkbcommon = b.lazyDependency("xkbcommon", .{});

        const scanner = Scanner.create(b, .{});

        const wayland = b.createModule(.{
            .root_source_file = scanner.result,
        });

        scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
        scanner.addSystemProtocol("stable/tablet/tablet-v2.xml");
        scanner.addSystemProtocol(
            "staging/cursor-shape/cursor-shape-v1.xml",
        );
        scanner.addSystemProtocol(
            "unstable/pointer-gestures/pointer-gestures-unstable-v1.xml",
        );

        scanner.generate("wl_compositor", 5);
        scanner.generate("wl_shm", 2);
        scanner.generate("wl_output", 4);
        scanner.generate("xdg_wm_base", 6);
        scanner.generate("wl_seat", 8);
        scanner.generate("wp_cursor_shape_manager_v1", 1);
        scanner.generate("zwp_pointer_gestures_v1", 3);

        fe_mod.addImport("wayland", wayland);
        fe_mod.linkSystemLibrary("wayland-client", .{ .needed = true });
        fe_mod.linkSystemLibrary("wayland-cursor", .{ .needed = true });

        if (xkbcommon) |m|
            fe_mod.addImport("xkbcommon", m.module("xkbcommon"));
        fe_mod.linkSystemLibrary("xkbcommon", .{ .needed = true });

        fe_mod.addSystemIncludePath(b.path("glib-2.0"));
        fe_mod.linkSystemLibrary("gio-2", .{ .needed = true });

        //- wgpu

        if (b.lazyDependency("wgpu_native", .{
            .target = target,
            .optimize = optimize,
        })) |wgpu| {
            fe_mod.addImport("wgpu", wgpu.module("wgpu"));
            fe_mod.linkSystemLibrary("wgpu_native", .{ .needed = true });
        }

        //- freetype

        if (b.lazyDependency("freetype", .{
            .target = target,
            .optimize = optimize,
        })) |freetype| {
            fe_mod.addImport("freetype", freetype.module("freetype"));
            fe_mod.linkLibrary(freetype.artifact("freetype"));
        }

        //- harfbuzz

        // @TODO: maybe use ghostty/pkg/harfbuzz
        fe_mod.addSystemIncludePath(b.path("harfbuzz"));
        fe_mod.linkSystemLibrary("harfbuzz", .{ .needed = true });

        //- fontconfig

        if (b.lazyDependency("fontconfig", .{
            .target = target,
            .optimize = optimize,
        })) |fontconfig| {
            fe_mod.addImport("fontconfig", fontconfig.module("fontconfig"));
            fe_mod.linkSystemLibrary("fontconfig", .{ .needed = true });
        }
    }

    fe_mod.addImport("cu", cu_mod);
    fe_mod.linkLibrary(cu_lib);

    if (tracy) |m| {
        fe_mod.addImport("tracy", m.module("tracy"));
        if (profile) {
            fe_mod.linkLibrary(m.artifact("tracy"));
            fe_mod.link_libcpp = true;
        }
    }

    if (pretty_print) |m|
        fe_mod.addImport("pretty", m.module("pretty"));

    const plugin_schema = getPluginSchema(b);
    fe_mod.addImport("plugin-schema", plugin_schema);

    const options = b.addOptions();
    options.addOption(std.log.Level, "log_level", log_level);
    options.addOption(bool, "valgrind", valgrind);
    fe_mod.addOptions("build_options", options);

    //- test plugin

    const plug_test_mod = createPluginModule(b, .{
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

    const plug_test_bin = addPlugin(b, .{
        .name = "test-plugin",
        .root_module = plug_test_mod,
    });

    if (!no_bin) {
        const install = plug_test_bin.installPlugin(b, "share/fe/plugins/test");
        fe_exe.step.dependOn(&install.step);
    }

    //- run

    if (!no_bin) {
        const run_cmd = b.addRunArtifact(fe_exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }
}

//= Plugin build helpers

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

pub fn createPluginModule(
    b: *std.Build,
    options: CreatePluginModuleOptions,
) *PluginModule {
    const wasm_target = b.resolveTargetQuery(.{
        // as of zig 0.14 support for wasm64 is not yet implemented:
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

            // probably part of threads support, which zig does not support
            // .atomics,

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

    pub fn installPlugin(
        compile: *PluginCompile,
        b: *std.Build,
        rel_out_dir: []const u8,
    ) *std.Build.Step.InstallArtifact {
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

    // not supported until we have wasm thread support
    // bin.shared_memory = true;

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
    const schema_install =
        b.addInstallFile(options.root_module.schema_path, "/");
    bin.step.dependOn(&schema_install.step);

    const compile = b.allocator.create(PluginCompile) catch @panic("oom");
    compile.* = .{
        .bin = bin,
        .schema_install = schema_install,
    };

    return compile;
}

pub fn getPluginLib(b: *std.Build) *std.Build.Module {
    const state = struct {
        var mod: ?*std.Build.Module = null;
    };

    return if (state.mod) |mod|
        mod
    else blk: {
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

        state.mod = mod;
        break :blk mod;
    };
}

pub fn getPluginSchema(b: *std.Build) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/plugin-schema/schema.zig"),
    });
}
