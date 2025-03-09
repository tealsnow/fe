const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_llvm = b.option(
        bool,
        "use_llvm",
        "switch to use llvm or not (defaults to false on debug builds true for release builds)",
    ) orelse if (optimize == .Debug) false else true;

    const exe = b.addExecutable(.{
        .name = "fe",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,

        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });
    b.installArtifact(exe);
    exe.linkLibC();

    exe.linkSystemLibrary2("SDL2", .{});
    exe.linkSystemLibrary2("SDL2_ttf", .{});
    exe.linkSystemLibrary2("fontconfig", .{});

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const check_step = b.step("check", "check");
    check_step.dependOn(&exe.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
