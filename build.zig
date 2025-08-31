const std = @import("std");
const builtin = @import("builtin");
pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const opt_use_shared = b.option(bool, "shared", "Make shared (default: false)") orelse false;

    const module = b.addModule("root", .{
        .root_source_file = b.path("src/zflecs.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addIncludePath(b.path("libs/flecs"));
    module.addCSourceFile(.{
        .file = b.path("libs/flecs/flecs.c"),
        .flags = &.{
            "-fno-sanitize=undefined",
            "-DFLECS_NO_CPP",
            "-DFLECS_USE_OS_ALLOC",
            if (builtin.mode == .Debug) "-DFLECS_SANITIZE" else "",
            if (opt_use_shared) "-DFLECS_SHARED" else "",
        },
    });

    const lib = b.addLibrary(.{
        .name = "flecs",
        .linkage = if (opt_use_shared) .dynamic else .static,
        .root_module = module,
    });
    lib.linkLibC();
    b.installArtifact(lib);

    if (target.result.os.tag == .windows) {
        lib.linkSystemLibrary("ws2_32");
    }
    const test_step = b.step("test", "Run zflecs tests");

    const tests = b.addTest(.{
        .name = "zflecs-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.addIncludePath(b.path("libs/flecs"));
    tests.linkLibrary(lib);
    tests.linkLibC();
    b.installArtifact(tests);

    test_step.dependOn(&b.addRunArtifact(tests).step);
}
