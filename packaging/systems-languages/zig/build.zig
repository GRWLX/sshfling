const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const common = b.path("common");

    const library = b.addStaticLibrary(.{
        .name = "sshfling_zig",
        .root_source_file = b.path("src/sshfling.zig"),
        .target = target,
        .optimize = optimize,
    });
    library.addIncludePath(common);
    library.addCSourceFile(.{ .file = b.path("common/sshfling_launcher.c"), .flags = &.{"-std=c11"} });
    library.linkLibC();
    b.installArtifact(library);

    const executable = b.addExecutable(.{
        .name = "sshfling-zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    executable.addIncludePath(common);
    executable.addCSourceFile(.{ .file = b.path("common/sshfling_launcher.c"), .flags = &.{"-std=c11"} });
    executable.linkLibC();
    b.installArtifact(executable);
}
