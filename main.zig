const std = @import("std");
const zlm = @import("zlm");

const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", {});
    @cInclude("GLFW/glfw3.h");
});

const DEBUG = std.debug.runtime_safety;

const VALIDATION_LAYERS = [_][]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const WIDTH = 800;
const HEIGHT = 600;

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const window = initWindow();
    const vulkan_instance = initVulkan(allocator);
    const physical_device = pickPhysicalDevice(allocator, vulkan_instance);
    _ = physical_device;

    // mainLoop
    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
    }
    // NOTE: worth checking what is gained by calling this, guessing resources will get freed by OS on program exit anyway?
    // cleanup
    c.vkDestroyInstance(vulkan_instance, null);
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

fn initVulkan(allocator: std.mem.Allocator) c.VkInstance {
    const app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Hello Triangle",
        .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_0,
    };

    var glfw_extension_count: u32 = 0;
    const glfw_extensions = c.glfwGetRequiredInstanceExtensions(&glfw_extension_count);
    const glfw_extensions_slice = glfw_extensions[0..glfw_extension_count];

    // checkExtensionsSupport
    var supported_extension_count: u32 = 0;
    _ = c.vkEnumerateInstanceExtensionProperties(null, &supported_extension_count, null);
    const supported_extensions = allocator.alloc(c.VkExtensionProperties, supported_extension_count) catch fatalQuiet();
    defer allocator.free(supported_extensions);
    _ = c.vkEnumerateInstanceExtensionProperties(null, &supported_extension_count, supported_extensions.ptr);
    for (glfw_extensions_slice) |glfw_x| {
        const len = std.mem.len(glfw_x);
        var found = false;
        std.debug.print("{s} required ... ", .{glfw_x});
        for (supported_extensions) |x| {
            if (std.mem.eql(u8, glfw_x[0..len], x.extensionName[0..len])) {
                std.debug.print("supported\n", .{});
                found = true;
                break;
            }
        }
        if (!found) {
            fatal("Unsupported extensions required");
        }
    }

    if (DEBUG) {
        // checkValidationLayerSupport
        var supported_layer_count: u32 = 0;
        _ = c.vkEnumerateInstanceLayerProperties(&supported_layer_count, null);
        const supported_layers = allocator.alloc(c.VkLayerProperties, supported_layer_count) catch fatalQuiet();
        defer allocator.free(supported_layers);
        _ = c.vkEnumerateInstanceLayerProperties(&supported_layer_count, supported_layers.ptr);
        for (VALIDATION_LAYERS) |v| {
            std.debug.print("{s} required ... ", .{v});
            var found = false;
            for (supported_layers) |s| {
                if (std.mem.eql(u8, v, s.layerName[0..v.len])) {
                    std.debug.print("supported\n", .{});
                    found = true;
                    break;
                }
            }
            if (!found) {
                fatal("Unsupported validation layers required");
            }
        }
    }

    const create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = glfw_extension_count,
        .ppEnabledExtensionNames = glfw_extensions,
        .enabledLayerCount = if (DEBUG) VALIDATION_LAYERS.len else 0,
        .ppEnabledLayerNames = if (DEBUG) @ptrCast(&VALIDATION_LAYERS) else null,
    };

    var result: c.VkInstance = undefined;
    const create_res = c.vkCreateInstance(&create_info, null, &result);
    if (create_res != c.VK_SUCCESS) {
        std.debug.print("create_res: {}\n", .{create_res});
        fatal("Vulkan instance creation failed");
    }
    return result;
}

fn pickPhysicalDevice(allocator: std.mem.Allocator, instance: c.VkInstance) c.VkPhysicalDevice {
    var device_count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(instance, &device_count, null);

    if (device_count == 0) {
        fatal("Failed to find any GPUs with Vulkan support");
    }

    const devices = allocator.alloc(c.VkPhysicalDevice, device_count) catch fatalQuiet();
    defer allocator.free(devices);
    _ = c.vkEnumeratePhysicalDevices(instance, &device_count, devices.ptr);

    // TODO - select the best available GPU, or at least prefer discrete GPU over integrated
    for (devices) |d| {
        const indices = findQueueFamilies(allocator, d);
        if (indices.graphics_family != null) {
            return d;
        }
    }
    fatal("Failed to find suitable physical GPU");
}

fn fatal(comptime mess: []const u8) noreturn {
    std.debug.print(mess, .{});
    std.process.exit(1);
}

fn fatalQuiet() noreturn {
    fatal("");
}

const QueueFamilyIndices = struct {
    graphics_family: ?u32,
};

fn findQueueFamilies(allocator: std.mem.Allocator, device: c.VkPhysicalDevice) QueueFamilyIndices {
    var indices = QueueFamilyIndices{
        .graphics_family = null,
    };

    var queue_family_count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);
    const queue_families = allocator.alloc(c.VkQueueFamilyProperties, queue_family_count) catch fatalQuiet();
    defer allocator.free(queue_families);
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

    for (queue_families, 0..) |qf, i| {
        std.debug.print("{}. {b}\n", .{ i, qf.queueFlags });
        if (qf.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            indices.graphics_family = @intCast(i);
        }
    }
    return indices;
}
