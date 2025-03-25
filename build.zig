const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_llvm = b.option(
        bool,
        "use_llvm",
        "switch to use llvm or not (defaults to false on debug builds true for release builds)",
    ) orelse if (optimize == .Debug) false else true;

    // wasmtime url
    {
        const wasmtime_version = "30.0.2";
        const wasmtime = b.step("print_wasmtime_url", "");
        const wasmtime_step = GetWasmtimeUrl.create(b, .initFromTarget(target.result, wasmtime_version));
        wasmtime.dependOn(&wasmtime_step.step);
    }

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

        mod.addImport("sdl3", sdl3.root_module);
        mod.linkLibrary(sdl3);

        mod.addImport("cu", cu.root_module);
        mod.linkLibrary(cu);

        mod.addImport("plugin-schema", plugin_schema);

        mod.addIncludePath(b.path("wasmtime/wasmtime/include/"));
        mod.addLibraryPath(b.path("wasmtime/wasmtime/lib/"));
        mod.linkSystemLibrary("wasmtime", .{ .needed = true });

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

const WasmtimeTarget = struct {
    /// The version tag to use for download
    version: []const u8,

    /// The architecture to download for,
    /// only aarch64, armv7/arm, i686/x86, riscv64gc/riscv64, s390x and x86_64 are supported
    arch: std.Target.Cpu.Arch,

    /// The os to download for,
    /// only android, linux, macos and windows are supported
    os: std.Target.Os.Tag,

    /// If not null, will use a different abi for the specified os,
    /// only mingw(windows), musl(linux) and android(linux) are supported
    abi: ?[]const u8 = null,

    pub fn initFromTarget(target: std.Target, version: []const u8) WasmtimeTarget {
        const assert = std.debug.assert;

        assert(switch (target.cpu.arch) {
            .aarch64, .arm, .x86, .riscv64, .s390x, .x86_64 => true,
            else => false,
        });
        assert(switch (target.os.tag) {
            .linux, .macos, .windows => true,
            else => false,
        });

        var abi: ?[]const u8 = null;
        switch (target.os.tag) {
            .windows => if (target.abi.isGnu()) {
                abi = "mingw";
            },
            .linux => if (target.abi.isMusl()) {
                abi = "musl";
            } else if (target.abi.isAndroid()) {
                abi = "android";
            },
            else => {},
        }

        return .{
            .version = version,
            .arch = target.cpu.arch,
            .os = target.os.tag,
            .abi = abi,
        };
    }

    pub fn resolveUrl(self: WasmtimeTarget, b: *std.Build) []const u8 {
        const os_abi = if (self.abi) |abi|
            abi
        else
            @tagName(self.os);

        const arch = switch (self.arch) {
            .arm => "armv7",
            .x86 => "i686",
            .riscv64 => "riscv64gc",
            else => @tagName(self.arch),
        };

        const fmt = "https://github.com/bytecodealliance/wasmtime/releases/download/v{[version]s}/" ++
            "wasmtime-v{[version]s}-{[arch]s}-{[os_abi]s}-c-api.tar.xz";
        return b.fmt(fmt, .{
            .version = self.version,
            .arch = arch,
            .os_abi = os_abi,
        });
    }
};

// I would have prefered to create a system that would download wasmtime and
// extract it. returning us the needed paths
// maybe one day
const GetWasmtimeUrl = struct {
    step: std.Build.Step,
    target: WasmtimeTarget,

    pub fn create(b: *std.Build, target: WasmtimeTarget) *GetWasmtimeUrl {
        const self = b.allocator.create(GetWasmtimeUrl) catch @panic("OOM");
        self.* = .{
            .step = .init(.{
                .id = .custom,
                .name = "get_wasmtime_url",
                .owner = b,
                .makeFn = make,
            }),
            .target = target,
        };
        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        const self: *GetWasmtimeUrl = @fieldParentPtr("step", step);
        const b = step.owner;
        _ = options;

        const url = self.target.resolveUrl(b);
        const stdout = std.io.getStdOut();
        try stdout.writeAll(url);
    }
};
