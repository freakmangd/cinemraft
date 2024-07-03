const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "cinemraft",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addIncludePath(b.path("src"));

    const opts = b.addOptions();
    opts.addOption(bool, "timing", b.option(bool, "timing", "show timings") orelse false);
    exe.root_module.addOptions("opts", opts);

    const znoise_dep = b.dependency("znoise", .{});

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
    if (target.result.os.tag == .linux) {
        raylib.root_module.addCMacro("_GLFW_X11", "");
        raylib.root_module.addCMacro("PLATFORM_DESKTOP_SDL", "");
    }
    exe.linkLibrary(raylib);

    exe.root_module.addIncludePath(raylib_dep.path("src"));
    exe.root_module.addCSourceFile(.{ .file = b.path("src/rlights.c") });

    exe.root_module.addImport("zentig", zrl.module("zentig"));
    exe.root_module.addImport("zrl", zrl.module("zentig-raylib"));

    exe.root_module.addImport("znoise", znoise_dep.module("root"));
    exe.linkLibrary(znoise_dep.artifact("FastNoiseLite"));

    exe.root_module.addImport("zmath", zentig_dep.module("zmath"));

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
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

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
