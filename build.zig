const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "cinemraft",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
    });
    exe.root_module.addIncludePath(b.path("src"));

    const opts = b.addOptions();
    opts.addOption(bool, "timing", b.option(bool, "timing", "show timings") orelse false);
    exe.root_module.addOptions("opts", opts);

    const znoise_dep = b.dependency("znoise", .{
        .target = target,
        .optimize = optimize,
    });

    const zentig_dep = b.dependency("zentig", .{});
    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });

    const zrl = b.dependency("zentig_raylib", .{
        .target = target,
        .optimize = optimize,
        .zentig_module_ptr = @as(usize, @intFromPtr(zentig_dep.module("zentig"))),
        .raylib_dep_ptr = @as(usize, @intFromPtr(raylib_dep)),
    });

    const raylib = zrl.artifact("raylib");
    switch (target.result.os.tag) {
        .linux => {
            raylib.root_module.addCMacro("_GLFW_X11", "");
            raylib.root_module.addCMacro("PLATFORM_DESKTOP_SDL", "");
        },
        .windows => {
            if (optimize != .Debug) exe.subsystem = .Windows;
        },
        else => {},
    }
    exe.linkLibrary(raylib);

    exe.root_module.addIncludePath(raylib_dep.path("src"));
    exe.root_module.addCSourceFile(.{ .file = b.path("src/rlights.c") });

    exe.root_module.addImport("zentig", zrl.module("zentig"));
    exe.root_module.addImport("zrl", zrl.module("zentig-raylib"));

    exe.root_module.addImport("znoise", znoise_dep.module("root"));
    exe.linkLibrary(znoise_dep.artifact("FastNoiseLite"));

    exe.root_module.addImport("zmath", zentig_dep.module("zmath"));

    const exe_check = b.addExecutable(.{
        .name = "study_timer",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_check.root_module.addIncludePath(raylib_dep.path("src"));
    exe_check.root_module.addCSourceFile(.{ .file = b.path("src/rlights.c") });
    exe_check.root_module.addImport("zentig", zrl.module("zentig"));
    exe_check.root_module.addImport("zrl", zrl.module("zentig-raylib"));
    exe_check.root_module.addImport("znoise", znoise_dep.module("root"));
    exe_check.linkLibrary(znoise_dep.artifact("FastNoiseLite"));
    exe_check.root_module.addImport("zmath", zentig_dep.module("zmath"));
    exe_check.linkLibrary(raylib);
    exe_check.root_module.addOptions("opts", opts);

    const check = b.step("check", "Check if foo compiles");
    check.dependOn(&exe_check.step);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_unit_tests.linkLibC();
    exe_unit_tests.root_module.addImport("zentig", zrl.module("zentig"));
    exe_unit_tests.root_module.addImport("zrl", zrl.module("zentig-raylib"));
    exe_unit_tests.linkLibrary(raylib);
    exe_unit_tests.root_module.addImport("zmath", zentig_dep.module("zmath"));

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
