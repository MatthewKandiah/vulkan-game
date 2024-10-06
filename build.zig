const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zlm = b.dependency("zlm", .{});

    const exe = b.addExecutable(.{
        .name = "vulkan-game",
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zlm", zlm.module("zlm"));
    exe.linkLibC();
    exe.linkSystemLibrary("glfw");
    exe.linkSystemLibrary("vulkan");
    b.installArtifact(exe);
}
