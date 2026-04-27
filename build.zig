//! Main build configuration for ZirconOS tools
//!
//! This build.zig file configures the compilation of hivex tools.

const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build hivex library using modules with libc linking
    const hivex_module = b.createModule(.{
        .root_source_file = b.path("src/tools/hivex/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const hivex_lib = b.addLibrary(.{
        .name = "hivex",
        .root_module = hivex_module,
    });

    // Build CLI tools
    inline for (.{
        "bcd_dump",
        "bcd_edit",
        "bcd_create",
        "hive_dump",
        "hive_merge",
        "hive_diff",
        "hivexml",
        "hivexregedit",
        "hivexget",
        "hivexsh",
        "debug_hive",
    }) |tool| {
        const tool_path = b.fmt("src/tools/hivex/bin/{s}.zig", .{tool});
        const exe_module = b.createModule(.{
            .root_source_file = b.path(tool_path),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

        // Add hivex as a dependency
        exe_module.addImport("hivex", hivex_module);

        const exe = b.addExecutable(.{
            .name = tool,
            .root_module = exe_module,
        });

        b.installArtifact(exe);
    }

    // Add tests
    const test_filters = b.option([]const []const u8, "test-filter", "Only run tests matching these filters");
    const test_module = b.createModule(.{
        .root_source_file = b.path("tests/tools/hivex/hive_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add hivex as a dependency
    test_module.addImport("hivex", hivex_module);

    const hivex_tests = b.addTest(.{
        .root_module = test_module,
    });

    if (test_filters) |filters| {
        hivex_tests.filters = filters;
    }

    const run_hivex_tests = b.addRunArtifact(hivex_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_hivex_tests.step);

    // Build step
    const build_step = b.step("build", "Build all hivex tools");
    build_step.dependOn(&hivex_lib.step);
}
