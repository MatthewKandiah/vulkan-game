const std = @import("std");

// not bothering to tidy up memory leaks, this isn't a long running process so it doesn't matter
pub fn build(b: *std.Build) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // compile shaders
    const input_dir_name = "shaders/";
    const output_dir_name = "shaders-out/";
    const shader_dir = try std.fs.openDirAbsolute(b.path(input_dir_name).getPath(b), .{ .iterate = true });

    var shader_dir_walker_1 = try shader_dir.walk(allocator);
    var shader_file_count: u32 = 0;
    while (true) {
        const file = try shader_dir_walker_1.next();
        if (file) |_| {
            shader_file_count += 1;
        } else break;
    }

    var filenames = try allocator.alloc([]const u8, shader_file_count);

    var shader_dir_walker_2 = try shader_dir.walk(allocator);
    var walk_2_count: u32 = 0;
    while (true) : (walk_2_count += 1) {
        const file = try shader_dir_walker_2.next();
        if (file) |f| {
            const filename = f.path;
            // copy because walker frees its allocated memory when `next` is called again
            const filename_copy = try allocator.alloc(u8, filename.len);
            std.mem.copyForwards(u8, filename_copy, filename);
            filenames[walk_2_count] = filename_copy;
        } else break;
    }

    var input_filenames = try allocator.alloc([]const u8, filenames.len);
    var output_filenames = try allocator.alloc([]const u8, filenames.len);
    for (filenames, 0..) |f, count| {
        const input_buf = try allocator.alloc(u8, input_dir_name.len + f.len);
        const output_buf = try allocator.alloc(u8, output_dir_name.len + f.len);

        _ = try std.fmt.bufPrint(input_buf, "{s}{s}", .{ input_dir_name, f });
        _ = try std.fmt.bufPrint(output_buf, "{s}{s}", .{ output_dir_name, f });

        input_filenames[count] = input_buf;
        output_filenames[count] = output_buf;
    }

    for (input_filenames, output_filenames) |is, os| {
        std.debug.print("i: {s}\no: {s}\n\n", .{ is, os });
        // TODO - okay now we've got a list of input filenames and output filenames, we want a step so `zig build shaders` will make all our glslc calls for us
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
