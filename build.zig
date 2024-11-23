const std = @import("std");
const os = std.os.linux;
const fs = std.fs;
const mem = std.mem;
const Step = std.Build.Step;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // This should be enabled when debugging
    const debugger_attached = b.option(
        bool,
        "debugger_attached",
        "whether to be compiled with the assumption that a dubugger will be attached",
    ) orelse false;

    // llvm increases compile time a lot, but optimizes better and gives better debugging symbols
    const use_llvm_lld = b.option(
        bool,
        "use_llvm",
        "Use llvm and lld (default: false) should be true for release, set to true of debugger_attached is true",
    ) orelse debugger_attached;

    const options = b.addOptions();
    options.addOption(bool, "debugger_attached", debugger_attached);

    const commonlib_src = b.path("src/common/common.zig");
    const commonlib = b.addSharedLibrary(.{
        .name = "common",
        .root_source_file = commonlib_src,
        .target = target,
        .optimize = optimize,
        // .version = .{ .major = 0, .minor = 0, .patch = 1 },
        .pic = true,

        .use_llvm = use_llvm_lld,
        .use_lld = use_llvm_lld,
    });

    commonlib.linkLibC();
    b.installArtifact(commonlib);

    commonlib.root_module.addOptions("options", options);

    const datetime = b.dependency("datetime", .{
        .target = target,
        .optimize = optimize,
    });
    commonlib.root_module.addImport("datetime", datetime.module("datetime"));

    const dynlib = b.addSharedLibrary(.{
        .name = "dynlib",
        .root_source_file = b.path("src/dynlib/dynlib.zig"),
        .target = target,
        .optimize = optimize,
        // .version = .{ .major = 0, .minor = 0, .patch = 1 },
        .pic = true,

        .use_llvm = use_llvm_lld,
        .use_lld = use_llvm_lld,
    });

    dynlib.linkLibC();
    b.installArtifact(dynlib);

    dynlib.linkLibrary(commonlib);
    dynlib.root_module.addImport("common", &commonlib.root_module);

    dynlib.root_module.addOptions("options", options);

    const dynlib_install = b.addInstallArtifact(dynlib, .{});

    const dynlib_step = b.step("dynlib", "Build only the dynlib shared library");
    dynlib_step.dependOn(&dynlib_install.step);

    const notify = NotifyRebuild.create(b);
    notify.step.dependOn(&dynlib_install.step);
    dynlib_step.dependOn(&notify.step);

    const watch_dynlib_cmd = b.addSystemCommand(&.{
        "watchexec",
        "-r", // restart if still running
        "-w", // watch dir:
        "src/dynlib/",
        "-e", // watch ext:
        "zig",
        "zig build dynlib", // command
    });
    const watch_dynlib_step = b.step("watch-dynlib", "Watch the dynamic library and rebuild on changes");
    watch_dynlib_step.dependOn(&watch_dynlib_cmd.step);

    const exe_src = b.path("src/exe/exe.zig");
    const exe = b.addExecutable(.{
        .name = "fe",
        .root_source_file = exe_src,
        .target = target,
        .optimize = optimize,

        .use_llvm = use_llvm_lld,
        .use_lld = use_llvm_lld,
    });

    exe.linkLibC();
    exe.linkSystemLibrary("SDL2");

    exe.linkLibrary(commonlib);
    exe.root_module.addImport("common", &commonlib.root_module);

    exe.root_module.addOptions("options", options);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const check_step = b.step("check", "Check");
    check_step.dependOn(&commonlib.step);
    check_step.dependOn(&dynlib.step);
    check_step.dependOn(&exe.step);

    // const exe_unit_tests = b.addTest(.{
    //     .root_source_file = exe_src,
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_exe_unit_tests.step);
}

const NotifyRebuild = struct {
    step: Step,
    builder: *std.Build,

    pub fn create(b: *std.Build) *NotifyRebuild {
        const self = b.allocator.create(NotifyRebuild) catch unreachable;
        self.* = .{
            .step = Step.init(.{
                .id = .custom,
                .name = "notify-rebuild",
                .owner = b,
                .makeFn = make,
            }),
            .builder = b,
        };
        return self;
    }

    fn make(step: *Step, prog_node: std.Progress.Node) !void {
        _ = step;

        var progress = prog_node.start("Notifying fe process", 2);
        defer progress.end();

        if (try findProcessByName("fe")) |pid| {
            progress.completeOne();
            _ = os.kill(pid, os.SIG.USR1);
            progress.completeOne();
        } else {
            progress.setCompletedItems(2);
        }
    }
};

fn findProcessByName(process_name: []const u8) !?os.pid_t {
    var proc_dir = try fs.openDirAbsolute("/proc", .{ .iterate = true });
    defer proc_dir.close();

    var iter = proc_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;

        const pid = std.fmt.parseInt(os.pid_t, entry.name, 10) catch continue;

        var cmdline_path_buf: [64]u8 = undefined;
        const cmdline_path = try std.fmt.bufPrint(
            &cmdline_path_buf,
            "/proc/{d}/cmdline",
            .{pid},
        );

        var cmdline_buf: [1024]u8 = undefined;
        const cmdline = try proc_dir.readFile(cmdline_path, &cmdline_buf);

        const process_path = mem.sliceTo(cmdline, 0);
        const found_name = fs.path.basename(process_path);

        if (mem.eql(u8, found_name, process_name)) {
            return pid;
        }
    }

    return null;
}
