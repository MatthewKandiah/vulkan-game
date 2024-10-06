const std = @import("std");
const zlm = @import("zlm");

const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", {});
    @cInclude("GLFW/glfw3.h");
});

const WIDTH = 800;
const HEIGHT = 600;

pub fn main() void {
    const window = initWindow();
    initVulkan();

    // mainLoop
    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
    }
    // NOTE: worth checking what is gained by calling this, guessing resources will get freed by OS on program exit anyway?
    // cleanup
    c.glfwDestroyWindow(window);
    c.glfwTerminate();
}

fn initWindow() *c.GLFWwindow {
    const init_res = c.glfwInit();
    if (init_res == c.GLFW_FALSE) {
        std.debug.print("init_res: {}\n", .{init_res});
        fatal("GLFW init failed");
    }

    // GLFW originally intended to create OpenGL context, this tells it not to
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

    return c.glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", null, null) orelse fatal("GLFW window creation failed");
}

fn initVulkan() void {}

fn fatal(comptime mess: []const u8) noreturn {
    std.debug.print(mess, .{});
    std.process.exit(1);
}

fn fatalQuiet() noreturn {
    fatal("");
}
