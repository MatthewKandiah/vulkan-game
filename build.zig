const std = @import("std");

pub fn build(b: *std.Build) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // compile shaders
    const shader_dir = try std.fs.openDirAbsolute(b.path("shaders/").getPath(b), .{ .iterate = true });
    var shader_dir_walker = try shader_dir.walk(allocator);
    while (true) {
        const file = try shader_dir_walker.next();
        if (file) |f| {
            std.debug.print("file: {s}\n", .{f.path});
        } else break;
        // TODO - we've got a list of input filenames, use them to generate an output filename automatically, then use these in the glslc call
    }

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
