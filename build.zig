const std = @import("std");

// not bothering to tidy up resources, this isn't a long running process so it doesn't matter
pub fn build(b: *std.Build) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    try setupShaderBuildStep(b, allocator);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "vulkan-game",
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.linkSystemLibrary("glfw");
    exe.linkSystemLibrary("vulkan");
    exe.addIncludePath(b.path("vendor"));
    exe.addCSourceFile(.{ .file = .{ .src_path = .{ .owner = b, .sub_path = "vendor/stb_image_impl.c" } } });
    const obj_mod = b.dependency("obj", .{ .target = target, .optimize = optimize }).module("obj");
    exe.root_module.addImport("obj", obj_mod);
    b.installArtifact(exe);
}

fn setupShaderBuildStep(b: *std.Build, allocator: std.mem.Allocator) !void {

    // compile shaders
    const input_dir_name = "shaders/";
    const output_dir_name = "shaders-out/";
    const shader_dir = try std.fs.openDirAbsolute(b.path(input_dir_name).getPath(b), .{ .iterate = true });
    try makeDirIfItDoesNotExist(b, output_dir_name);

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
        const extension = ".spv";
        const input_buf = try allocator.alloc(u8, input_dir_name.len + f.len);
        const output_buf = try allocator.alloc(u8, output_dir_name.len + f.len + extension.len);

        _ = try std.fmt.bufPrint(input_buf, "{s}{s}", .{ input_dir_name, f });
        _ = try std.fmt.bufPrint(output_buf, "{s}{s}{s}", .{ output_dir_name, f, extension });

        input_filenames[count] = input_buf;
        output_filenames[count] = output_buf;
    }

    var compile_shader_runs = try allocator.alloc(*std.Build.Step.Run, filenames.len);
    for (input_filenames, output_filenames, 0..) |in_name, out_name, count| {
        const shader_compile_run = b.addSystemCommand(&.{"glslc"});
        shader_compile_run.addFileArg(std.Build.LazyPath{ .src_path = .{ .owner = b, .sub_path = in_name } });
        shader_compile_run.addArg("-o");
        shader_compile_run.addFileArg(std.Build.LazyPath{ .src_path = .{ .owner = b, .sub_path = out_name } });
        compile_shader_runs[count] = shader_compile_run;
    }

    const compile_shaders_step = b.step("shaders", "Compile shaders");
    for (compile_shader_runs) |run| {
        compile_shaders_step.dependOn(&run.step);
    }
}

fn makeDirIfItDoesNotExist(b: *std.Build, dir_name: []const u8) !void {
    var open_dir_result = std.fs.openDirAbsolute(b.path(dir_name).getPath(b), .{});
    if (open_dir_result) |*output_dir| {
        output_dir.close();
    } else |_| {
        try std.fs.makeDirAbsolute(b.path(dir_name).getPath(b));
    }
}
