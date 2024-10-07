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
    const surface = createSurface(vulkan_instance, window);
    const physical_device = pickPhysicalDevice(allocator, vulkan_instance, surface);
    const queue_family_indices = findQueueFamilies(allocator, physical_device, surface);
    const logical_device = createLogicalDevice(physical_device, queue_family_indices);
    var graphics_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(logical_device, queue_family_indices.graphics_family.?, 0, &graphics_queue);
    var present_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(logical_device, queue_family_indices.present_family.?, 0, &present_queue);

    // mainLoop
    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
    }
    // NOTE: worth checking what is gained by calling this, guessing resources will get freed by OS on program exit anyway?
    // cleanup
    c.vkDestroyDevice(logical_device, null);
    c.vkDestroySurfaceKHR(vulkan_instance, surface, null);
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

fn createSurface(instance: c.VkInstance, window: *c.GLFWwindow) c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;
    const res = c.glfwCreateWindowSurface(instance, window, null, &surface);
    if (res != c.VK_SUCCESS) {
        std.debug.print("res: {}\n", .{res});
        fatal("Failed to create glfw surface");
    }
    return surface;
}

fn pickPhysicalDevice(allocator: std.mem.Allocator, instance: c.VkInstance, surface: c.VkSurfaceKHR) c.VkPhysicalDevice {
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
        // isDeviceSuitable
        const indices = findQueueFamilies(allocator, d, surface);
        if (indices.isComplete()) {
            return d;
        }
    }
    fatal("Failed to find suitable physical GPU");
}

fn createLogicalDevice(physical_device: c.VkPhysicalDevice, family_indices: QueueFamilyIndices) c.VkDevice {
    const graphics_queue_create_info = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = family_indices.graphics_family.?,
        .queueCount = 1,
        .pQueuePriorities = &[_]f32{1},
    };
    const present_queue_create_info = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = family_indices.present_family.?,
        .queueCount = 1,
        .pQueuePriorities = &[_]f32{1},
    };
    const queue_create_infos = [_]c.VkDeviceQueueCreateInfo{
        graphics_queue_create_info,
        present_queue_create_info,
    };
    const device_features = std.mem.zeroes(c.VkPhysicalDeviceFeatures);
    const create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queue_create_infos,
        .queueCreateInfoCount = queue_create_infos.len,
        .pEnabledFeatures = &device_features,
        .enabledExtensionCount = 0,
        .enabledLayerCount = 0,
    };
    var device: c.VkDevice = undefined;
    const res = c.vkCreateDevice(physical_device, &create_info, null, &device);
    if (res != c.VK_SUCCESS) {
        std.debug.print("res: {}", .{res});
        fatal("Failed to create logical device");
    }
    return device;
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
    present_family: ?u32,

    const Self = @This();

    fn isComplete(self: Self) bool {
        return self.graphics_family != null and self.present_family != null;
    }
};

fn findQueueFamilies(allocator: std.mem.Allocator, device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) QueueFamilyIndices {
    var indices = QueueFamilyIndices{
        .graphics_family = null,
        .present_family = null,
    };

    var queue_family_count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);
    const queue_families = allocator.alloc(c.VkQueueFamilyProperties, queue_family_count) catch fatalQuiet();
    defer allocator.free(queue_families);
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

    for (queue_families, 0..) |qf, i| {
        if (qf.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            indices.graphics_family = @intCast(i);
        }

        var present_support: u32 = c.VK_FALSE;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface, &present_support);
        if (present_support != c.VK_FALSE) {
            indices.present_family = @intCast(i);
        }
    }
    return indices;
}
