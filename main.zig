const std = @import("std");
const zlm = @import("zlm");

const c = @cImport({
    @cDefine("false", "0");
    @cDefine("GLFW_INCLUDE_VULKAN", {});
    @cInclude("GLFW/glfw3.h");
});

pub fn main() void {
    _ = c.glfwInit();
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    const windowPtr = c.glfwCreateWindow(800, 600, "Vulkan Window", null, null);

    var extension_count: u32 = undefined;
    _ = c.vkEnumerateInstanceExtensionProperties(null, &extension_count, null);
    std.debug.print("Extensions supported: {}\n", .{extension_count});

    const mat = zlm.Mat4{ .fields = [4][4]f32{
        [4]f32{ 1, 0, 0, 0 },
        [4]f32{ 0, 2, 0, 0 },
        [4]f32{ 0, 0, 3, 0 },
        [4]f32{ 0, 0, 0, 4 },
    } };
    const vec = zlm.Vec4.new(1, 2, 3, 4);

    const product = zlm.Vec4.transform(vec, mat);
    std.debug.print("Product: {any}\n", .{product});

    while (c.glfwWindowShouldClose(windowPtr) == c.false) {
        c.glfwPollEvents();
    }

    c.glfwDestroyWindow(windowPtr);
    c.glfwTerminate();
}
