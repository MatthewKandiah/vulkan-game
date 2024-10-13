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

const DEVICE_EXTENSIONS = [_][]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const WIDTH = 800;
const HEIGHT = 600;

const VERT_SHADER_FILENAME = "/home/matt/code/vulkan-game/shaders-out/shader.vert.spv";
const FRAG_SHADER_FILENAME = "/home/matt/code/vulkan-game/shaders-out/shader.frag.spv";
const VERT_SHADER_RAW: []const u8 align(4) = @embedFile(VERT_SHADER_FILENAME);
const FRAG_SHADER_RAW: []const u8 align(4) = @embedFile(FRAG_SHADER_FILENAME);

const vertices = [_]Vertex{
    Vertex{ .pos = zlm.vec2(0, -0.5), .color = zlm.vec3(1, 0, 0) },
    Vertex{ .pos = zlm.vec2(0.5, 0.5), .color = zlm.vec3(0, 1, 0) },
    Vertex{ .pos = zlm.vec2(-0.5, 0.5), .color = zlm.vec3(0, 0, 1) },
};

const MAX_FRAMES_IN_FLIGHT = 2;

// nasty global state variable
// apparently not all Vulkan drivers emit expected events on window resize, this is a way to ensure we catch those cases too
var framebuffer_resized = false;
fn framebufferResizedCallback(_: *c.GLFWwindow, _: i32, _: i32) void {
    framebuffer_resized = true;
}

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const window = initWindow();
    _ = c.glfwSetFramebufferSizeCallback(window, @ptrCast(&framebufferResizedCallback));
    const vulkan_instance = initVulkan(allocator);
    const surface = createSurface(vulkan_instance, window);
    const physical_device = pickPhysicalDevice(allocator, vulkan_instance, surface);
    const queue_family_indices = findQueueFamilies(allocator, physical_device, surface);
    const logical_device = createLogicalDevice(physical_device, queue_family_indices);

    const create_swapchain_res = createSwapchain(
        allocator,
        surface,
        window,
        queue_family_indices,
        physical_device,
        logical_device,
    );
    var swapchain = create_swapchain_res.swapchain.?;
    var swapchain_image_format = create_swapchain_res.format;
    var swapchain_extent = create_swapchain_res.extent;

    const create_image_views_res = createImageViews(
        allocator,
        logical_device,
        swapchain,
        swapchain_image_format,
    );
    var swapchain_image_views = create_image_views_res.swapchain_image_views;
    var swapchain_images = create_image_views_res.swapchain_images;

    var graphics_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(logical_device, queue_family_indices.graphics_family.?, 0, &graphics_queue);
    var present_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(logical_device, queue_family_indices.present_family.?, 0, &present_queue);

    const render_pass = createRenderPass(logical_device, swapchain_image_format);

    const create_pipeline_result = createGraphicsPipeline(logical_device, swapchain_extent, render_pass);
    const pipeline_layout = create_pipeline_result.pipeline_layout;
    const graphics_pipeline = create_pipeline_result.pipeline;
    var swapchain_framebuffers = createFramebuffers(
        allocator,
        swapchain_image_views,
        render_pass,
        swapchain_extent,
        logical_device,
    );

    const command_pool = createCommandPool(queue_family_indices, logical_device);

    const command_buffers: [MAX_FRAMES_IN_FLIGHT]c.VkCommandBuffer = createCommandBuffers(
        command_pool,
        logical_device,
    );

    var image_available_semaphores: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = undefined;
    var render_finished_semaphores: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = undefined;
    var in_flight_fences: [MAX_FRAMES_IN_FLIGHT]c.VkFence = undefined;
    initialiseSyncObjects(logical_device, &image_available_semaphores, &render_finished_semaphores, &in_flight_fences);

    var current_frame_index: u32 = 0;
    // mainLoop
    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
        drawFrame(
            allocator,
            logical_device,
            &in_flight_fences[current_frame_index],
            @ptrCast(&swapchain),
            image_available_semaphores[current_frame_index],
            render_finished_semaphores[current_frame_index],
            command_buffers[current_frame_index],
            render_pass,
            &swapchain_framebuffers,
            &swapchain_extent,
            &swapchain_image_format,
            graphics_pipeline,
            graphics_queue,
            present_queue,
            surface,
            window,
            queue_family_indices,
            physical_device,
            &swapchain_image_views,
            &swapchain_images,
        );
        current_frame_index = (current_frame_index + 1) % MAX_FRAMES_IN_FLIGHT;

        const device_idle_res = c.vkDeviceWaitIdle(logical_device);
        fatalIfNotSuccess(device_idle_res, "Failed waiting for logical device to be idle");
    }

    // cleanup
    cleanupSwapchain(
        allocator,
        logical_device,
        swapchain_framebuffers,
        swapchain,
        swapchain_image_views,
        swapchain_images,
    );

    for (
        image_available_semaphores,
        render_finished_semaphores,
        in_flight_fences,
    ) |
        image_available_semaphore,
        render_finished_semaphore,
        in_flight_fence,
    | {
        c.vkDestroySemaphore(logical_device, image_available_semaphore, null);
        c.vkDestroySemaphore(logical_device, render_finished_semaphore, null);
        c.vkDestroyFence(logical_device, in_flight_fence, null);
    }
    c.vkDestroyCommandPool(logical_device, command_pool, null);
    c.vkDestroyPipeline(logical_device, graphics_pipeline, null);
    c.vkDestroyPipelineLayout(logical_device, pipeline_layout, null);
    c.vkDestroyRenderPass(logical_device, render_pass, null);
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
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_TRUE);

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
    fatalIfNotSuccess(create_res, "Failed to create Vulkan instance");
    return result;
}

fn createSurface(instance: c.VkInstance, window: *c.GLFWwindow) c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;
    const res = c.glfwCreateWindowSurface(instance, window, null, &surface);
    fatalIfNotSuccess(res, "Failed to create glfw surface");
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
    for (devices) |device| {
        // isDeviceSuitable
        const extensions_supported = checkDeviceExtensionSupport(allocator, device);
        const indices = findQueueFamilies(allocator, device, surface);
        if (indices.isComplete() and extensions_supported) {
            // querySwapchainSupport
            var swapchain_capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
            _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &swapchain_capabilities);

            var surface_format_count: u32 = undefined;
            _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &surface_format_count, null);
            if (surface_format_count == 0) continue;

            var present_mode_count: u32 = undefined;
            _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, null);
            if (present_mode_count == 0) continue;

            return device;
        }
    }
    fatal("Failed to find suitable physical GPU");
}

fn chooseSwapExtent(window: *c.GLFWwindow, capabilities: c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    }
    var width: i32 = undefined;
    var height: i32 = undefined;
    c.glfwGetFramebufferSize(window, &width, &height);
    return c.VkExtent2D{
        .width = std.math.clamp(
            @as(u32, @intCast(width)),
            capabilities.minImageExtent.width,
            capabilities.maxImageExtent.width,
        ),
        .height = std.math.clamp(
            @as(u32, @intCast(height)),
            capabilities.minImageExtent.height,
            capabilities.maxImageExtent.height,
        ),
    };
}

fn chooseSwapPresentMode(available_present_modes: []c.VkPresentModeKHR) c.VkPresentModeKHR {
    for (available_present_modes) |available_mode| {
        if (available_mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            return available_mode;
        }
    }
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn chooseSwapSurfaceFormat(available_formats: []c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
    for (available_formats) |available_format| {
        if (available_format.format == c.VK_FORMAT_B8G8R8A8_SRGB and available_format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return available_format;
        }
    }
    return available_formats[0];
}

fn checkDeviceExtensionSupport(allocator: std.mem.Allocator, device: c.VkPhysicalDevice) bool {
    var extension_count: u32 = undefined;
    _ = c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, null);

    const available_extensions = allocator.alloc(c.VkExtensionProperties, extension_count) catch fatalQuiet();
    defer allocator.free(available_extensions);
    _ = c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, available_extensions.ptr);

    var all_found = true;
    for (DEVICE_EXTENSIONS) |required_extension| {
        var found = false;
        for (available_extensions) |available_extension| {
            const len = required_extension.len;
            if (std.mem.eql(u8, required_extension, available_extension.extensionName[0..len])) {
                found = true;
                break;
            }
        }
        if (!found) {
            all_found = false;
            break;
        }
    }
    return all_found;
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
        .enabledExtensionCount = DEVICE_EXTENSIONS.len,
        .ppEnabledExtensionNames = @ptrCast(&DEVICE_EXTENSIONS),
        .enabledLayerCount = 0,
    };
    var device: c.VkDevice = undefined;
    const res = c.vkCreateDevice(physical_device, &create_info, null, &device);
    fatalIfNotSuccess(res, "Failed to create logical device");
    return device;
}

fn fatal(comptime mess: []const u8) noreturn {
    std.debug.print(mess, .{});
    std.process.exit(1);
}

fn fatalQuiet() noreturn {
    fatal("");
}

fn fatalIfNotSuccess(res: c.VkResult, comptime mess: []const u8) void {
    if (res != c.VK_SUCCESS) {
        std.debug.print("res: {}\n", .{res});
        fatal(mess);
    }
}

const QueueFamilyIndices = struct {
    graphics_family: ?u32,
    present_family: ?u32,

    const Self = @This();

    fn isComplete(self: Self) bool {
        return self.graphics_family != null and self.present_family != null;
    }
};

// TODO - I've done this lazily and just picked whatever works
//        Would be better to preferentially pick a single index that can handle both families
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

const CreateSwapchainResult = struct {
    swapchain: c.VkSwapchainKHR,
    format: c.VkFormat,
    extent: c.VkExtent2D,
};

fn createSwapchain(
    allocator: std.mem.Allocator,
    surface: c.VkSurfaceKHR,
    window: *c.GLFWwindow,
    queue_family_indices: QueueFamilyIndices,
    physical_device: c.VkPhysicalDevice,
    logical_device: c.VkDevice,
) CreateSwapchainResult {
    var swapchain_capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &swapchain_capabilities);
    var swapchain_surface_format_count: u32 = undefined;
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &swapchain_surface_format_count, null);
    const swapchain_surface_formats = allocator.alloc(c.VkSurfaceFormatKHR, swapchain_surface_format_count) catch fatalQuiet();
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &swapchain_surface_format_count, swapchain_surface_formats.ptr);
    var swapchain_present_mode_count: u32 = undefined;
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &swapchain_present_mode_count, null);
    const swapchain_present_modes = allocator.alloc(c.VkPresentModeKHR, swapchain_present_mode_count) catch fatalQuiet();
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &swapchain_present_mode_count, swapchain_present_modes.ptr);

    const swapchain_surface_format = chooseSwapSurfaceFormat(swapchain_surface_formats);
    const swapchain_present_mode = chooseSwapPresentMode(swapchain_present_modes);
    const swapchain_extent = chooseSwapExtent(window, swapchain_capabilities);
    allocator.free(swapchain_surface_formats);
    allocator.free(swapchain_present_modes);
    var swapchain_image_count: u32 = swapchain_capabilities.minImageCount + 1;
    if (swapchain_capabilities.maxImageCount > 0 and swapchain_image_count > swapchain_capabilities.maxImageCount) {
        swapchain_image_count = swapchain_capabilities.maxImageCount;
    }

    var create_swapchain_info = std.mem.zeroes(c.VkSwapchainCreateInfoKHR);
    create_swapchain_info.sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    create_swapchain_info.surface = surface;
    create_swapchain_info.minImageCount = swapchain_image_count;
    create_swapchain_info.imageFormat = swapchain_surface_format.format;
    create_swapchain_info.imageColorSpace = swapchain_surface_format.colorSpace;
    create_swapchain_info.imageExtent = swapchain_extent;
    create_swapchain_info.imageArrayLayers = 1;
    // NOTE - this imageUsage is used to render an image directly to the screen
    //        if you want to perform post-processing you will want to render to another image first
    //        in that case consider using c.VK_IMAGE_USAGE_TRANSFER_DST_BIT and a memory operation
    //        to transfer the rendered image to a swapchain image
    create_swapchain_info.imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    if (queue_family_indices.graphics_family != queue_family_indices.present_family) {
        create_swapchain_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        create_swapchain_info.queueFamilyIndexCount = 2;
        create_swapchain_info.pQueueFamilyIndices = &[2]u32{ queue_family_indices.graphics_family.?, queue_family_indices.present_family.? };
    } else {
        create_swapchain_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        create_swapchain_info.queueFamilyIndexCount = 0;
        create_swapchain_info.pQueueFamilyIndices = null;
    }
    create_swapchain_info.preTransform = swapchain_capabilities.currentTransform;
    create_swapchain_info.compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    create_swapchain_info.presentMode = swapchain_present_mode;
    create_swapchain_info.clipped = c.VK_TRUE;
    create_swapchain_info.oldSwapchain = @ptrCast(c.VK_NULL_HANDLE);
    var swapchain: c.VkSwapchainKHR = undefined;
    const create_swapchain_res = c.vkCreateSwapchainKHR(logical_device, &create_swapchain_info, null, &swapchain);
    fatalIfNotSuccess(create_swapchain_res, "Failed to create swapchain");
    return CreateSwapchainResult{
        .swapchain = swapchain,
        .extent = swapchain_extent,
        .format = swapchain_surface_format.format,
    };
}

const CreateImageViewsResult = struct {
    swapchain_image_views: []c.VkImageView,
    swapchain_images: []c.VkImage,
};

fn createImageViews(
    allocator: std.mem.Allocator,
    logical_device: c.VkDevice,
    swapchain: c.VkSwapchainKHR,
    swapchain_image_format: c.VkFormat,
) CreateImageViewsResult {
    var swapchain_image_count: u32 = undefined;
    _ = c.vkGetSwapchainImagesKHR(logical_device, swapchain, &swapchain_image_count, null);
    const swapchain_images = allocator.alloc(c.VkImage, swapchain_image_count) catch fatalQuiet();
    _ = c.vkGetSwapchainImagesKHR(logical_device, swapchain, &swapchain_image_count, swapchain_images.ptr);

    const swapchain_image_views = allocator.alloc(c.VkImageView, swapchain_image_count) catch fatalQuiet();
    for (swapchain_images, 0..) |image, i| {
        var image_view_create_info = std.mem.zeroes(c.VkImageViewCreateInfo);
        image_view_create_info.sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        image_view_create_info.image = image;
        image_view_create_info.viewType = c.VK_IMAGE_VIEW_TYPE_2D;
        image_view_create_info.format = swapchain_image_format;
        image_view_create_info.components = .{
            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
        };
        image_view_create_info.subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        };
        const image_view_create_res = c.vkCreateImageView(logical_device, &image_view_create_info, null, &swapchain_image_views[i]);
        fatalIfNotSuccess(image_view_create_res, "Failed to create image view");
    }

    return CreateImageViewsResult{
        .swapchain_image_views = swapchain_image_views,
        .swapchain_images = swapchain_images,
    };
}

fn createRenderPass(logical_device: c.VkDevice, image_format: c.VkFormat) c.VkRenderPass {
    const color_attachment = c.VkAttachmentDescription{
        .format = image_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    const color_attachment_ref = c.VkAttachmentReference{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass = c.VkSubpassDescription{
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_ref,
    };

    const subpass_dependency = c.VkSubpassDependency{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };

    var render_pass: c.VkRenderPass = undefined;
    const render_pass_create_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &subpass_dependency,
    };
    const render_pass_create_res = c.vkCreateRenderPass(logical_device, &render_pass_create_info, null, &render_pass);
    fatalIfNotSuccess(render_pass_create_res, "Failed to create render pass");
    return render_pass;
}

const CreateGraphicsPipelineResult = struct {
    pipeline_layout: c.VkPipelineLayout,
    pipeline: c.VkPipeline,
};

fn createGraphicsPipeline(logical_device: c.VkDevice, swapchain_extent: c.VkExtent2D, render_pass: c.VkRenderPass) CreateGraphicsPipelineResult {
    const vert_shader_module = createShaderModule(VERT_SHADER_RAW, logical_device);
    const frag_shader_module = createShaderModule(FRAG_SHADER_RAW, logical_device);

    const vert_shader_stage_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vert_shader_module,
        .pName = "main",
        .pNext = null,
        .pSpecializationInfo = null,
        .flags = 0,
    };

    const frag_shader_stage_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = frag_shader_module,
        .pName = "main",
        .pNext = null,
        .pSpecializationInfo = null,
        .flags = 0,
    };

    const shader_stages = [_]c.VkPipelineShaderStageCreateInfo{ vert_shader_stage_info, frag_shader_stage_info };

    const dynamic_states = [_]c.VkDynamicState{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
    const dynamic_state = c.VkPipelineDynamicStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamic_states.len,
        .pDynamicStates = &dynamic_states,
        .pNext = null,
        .flags = 0,
    };

    const binding_description = Vertex.getBindingDescription();
    const attribute_descriptions = Vertex.getAttributeDescriptions();

    const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &binding_description,
        .vertexAttributeDescriptionCount = attribute_descriptions.len,
        .pVertexAttributeDescriptions = &attribute_descriptions,
    };

    const input_assembly = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
        .pNext = null,
        .flags = 0,
    };

    const viewport = c.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(swapchain_extent.width),
        .height = @floatFromInt(swapchain_extent.height),
        .minDepth = 0,
        .maxDepth = 1,
    };
    _ = viewport; // autofix

    const scissor = c.VkRect2D{
        .offset = c.VkOffset2D{ .x = 0, .y = 0 },
        .extent = swapchain_extent,
    };
    _ = scissor; // autofix

    // viewports and scissors don't have to be set here because we're setting them dynamically at drawing time
    const viewport_state = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };

    const rasterizer = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL, // change to c.VK_POLYGON_MODE_LINE for wireframe
        .lineWidth = 1,
        .cullMode = c.VK_CULL_MODE_BACK_BIT,
        .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
        .depthBiasConstantFactor = 0,
        .depthBiasClamp = 0,
        .depthBiasSlopeFactor = 0,
    };

    const multisampling = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = c.VK_FALSE,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        .minSampleShading = 1,
        .pSampleMask = null,
        .alphaToCoverageEnable = c.VK_FALSE,
        .alphaToOneEnable = c.VK_FALSE,
    };

    const color_blend_attachment = c.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = c.VK_FALSE,
    };

    const color_blending = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = c.VK_FALSE,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
    };

    var pipeline_layout: c.VkPipelineLayout = undefined;
    const pipeline_layout_create_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    };
    const pipeline_layout_create_res = c.vkCreatePipelineLayout(logical_device, &pipeline_layout_create_info, null, &pipeline_layout);
    fatalIfNotSuccess(pipeline_layout_create_res, "Failed to create pipeline layout");

    const pipeline_create_info = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = &shader_stages,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = null,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state,
        .layout = pipeline_layout,
        .renderPass = render_pass,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
    };

    var graphics_pipeline: c.VkPipeline = undefined;
    const graphics_pipeline_create_res = c.vkCreateGraphicsPipelines(logical_device, null, 1, &pipeline_create_info, null, &graphics_pipeline);
    fatalIfNotSuccess(graphics_pipeline_create_res, "Failed to create graphics pipeline");

    c.vkDestroyShaderModule(logical_device, vert_shader_module, null);
    c.vkDestroyShaderModule(logical_device, frag_shader_module, null);
    return .{
        .pipeline_layout = pipeline_layout,
        .pipeline = graphics_pipeline,
    };
}

fn createFramebuffers(
    allocator: std.mem.Allocator,
    swapchain_image_views: []c.VkImageView,
    render_pass: c.VkRenderPass,
    swapchain_extent: c.VkExtent2D,
    logical_device: c.VkDevice,
) []c.VkFramebuffer {
    const swapchain_framebuffers = allocator.alloc(c.VkFramebuffer, swapchain_image_views.len) catch fatalQuiet();
    for (0..swapchain_image_views.len) |i| {
        const framebuffer_create_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass,
            .attachmentCount = 1,
            .pAttachments = &swapchain_image_views[i],
            .width = swapchain_extent.width,
            .height = swapchain_extent.height,
            .layers = 1,
        };
        const framebuffer_create_res = c.vkCreateFramebuffer(logical_device, &framebuffer_create_info, null, &swapchain_framebuffers[i]);
        fatalIfNotSuccess(framebuffer_create_res, "Failed to create framebuffer");
    }
    return swapchain_framebuffers;
}

fn createCommandPool(queue_family_indices: QueueFamilyIndices, logical_device: c.VkDevice) c.VkCommandPool {
    const pool_create_info = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queue_family_indices.graphics_family.?,
    };
    var command_pool: c.VkCommandPool = undefined;
    const pool_create_res = c.vkCreateCommandPool(logical_device, &pool_create_info, null, &command_pool);
    fatalIfNotSuccess(pool_create_res, "Failed to create command pool");
    return command_pool;
}

fn createCommandBuffers(
    command_pool: c.VkCommandPool,
    logical_device: c.VkDevice,
) [MAX_FRAMES_IN_FLIGHT]c.VkCommandBuffer {
    const alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = MAX_FRAMES_IN_FLIGHT,
    };
    var command_buffers: [MAX_FRAMES_IN_FLIGHT]c.VkCommandBuffer = undefined;
    const alloc_res = c.vkAllocateCommandBuffers(logical_device, &alloc_info, &command_buffers);
    fatalIfNotSuccess(alloc_res, "Failed to allocate command buffers");
    return command_buffers;
}

fn createShaderModule(comptime shader: []const u8, logical_device: c.VkDevice) c.VkShaderModule {
    // TODO - this smells very system dependent
    //        presumably there's some way to sniff out the endianess we're going to write the shader to file with
    //        then we could make this more sane
    //        alternatively, the glslc people also have a library that let's you compile shaders at runtime
    //        that might avoid all this
    var processed_shader: [shader.len / 2]u16 align(4) = undefined;
    for (0..processed_shader.len) |i| {
        const buf = [2]u8{
            shader[2 * i],
            shader[2 * i + 1],
        };
        processed_shader[i] = std.mem.readInt(u16, &buf, .little);
    }
    const module_create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = processed_shader.len * 2,
        .pCode = @ptrCast(&processed_shader),
        .pNext = null,
        .flags = 0,
    };
    var shader_module: c.VkShaderModule = undefined;
    const module_create_res = c.vkCreateShaderModule(
        logical_device,
        &module_create_info,
        null,
        &shader_module,
    );
    fatalIfNotSuccess(module_create_res, "Failed to create shader module");
    return shader_module;
}

fn recordCommandBuffer(
    command_buffer: c.VkCommandBuffer,
    image_index: u32,
    render_pass: c.VkRenderPass,
    swapchain_framebuffers: []c.VkFramebuffer,
    swapchain_extent: c.VkExtent2D,
    graphics_pipeline: c.VkPipeline,
) void {
    const begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    };
    const begin_res = c.vkBeginCommandBuffer(command_buffer, &begin_info);
    fatalIfNotSuccess(begin_res, "Failed to begin recording command buffer");

    // clear to opaque black
    const clear_color = c.VkClearValue{
        .color = .{ .float32 = .{ 0, 0, 0, 1 } },
    };

    const render_pass_info = c.VkRenderPassBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = render_pass,
        .framebuffer = swapchain_framebuffers[image_index],
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = swapchain_extent,
        },
        .clearValueCount = 1,
        .pClearValues = &clear_color,
    };

    c.vkCmdBeginRenderPass(
        command_buffer,
        &render_pass_info,
        c.VK_SUBPASS_CONTENTS_INLINE,
    );

    c.vkCmdBindPipeline(
        command_buffer,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        graphics_pipeline,
    );

    const viewport = c.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(swapchain_extent.width),
        .height = @floatFromInt(swapchain_extent.height),
        .minDepth = 0,
        .maxDepth = 1,
    };
    c.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

    const scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain_extent,
    };
    c.vkCmdSetScissor(command_buffer, 0, 1, &scissor);

    c.vkCmdDraw(command_buffer, 3, 1, 0, 0);

    c.vkCmdEndRenderPass(command_buffer);

    const end_command_buffer_res = c.vkEndCommandBuffer(command_buffer);
    fatalIfNotSuccess(end_command_buffer_res, "Failed to end command buffer");
}

fn initialiseSyncObjects(
    logical_device: c.VkDevice,
    image_available_semaphores: []c.VkSemaphore,
    render_finished_semaphores: []c.VkSemaphore,
    in_flight_fences: []c.VkFence,
) void {
    const semaphore_create_info = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    const fence_create_info = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    for (
        image_available_semaphores,
        render_finished_semaphores,
        in_flight_fences,
    ) |
        *image_available_semaphore,
        *render_finished_semaphore,
        *in_flight_fence,
    | {
        const image_available_semaphore_res = c.vkCreateSemaphore(logical_device, &semaphore_create_info, null, image_available_semaphore);
        fatalIfNotSuccess(image_available_semaphore_res, "Failed to create image available semaphore");

        const render_finished_semaphore_res = c.vkCreateSemaphore(logical_device, &semaphore_create_info, null, render_finished_semaphore);
        fatalIfNotSuccess(render_finished_semaphore_res, "Failed to create render finished semaphore");

        const in_flight_fence_res = c.vkCreateFence(logical_device, &fence_create_info, null, in_flight_fence);
        fatalIfNotSuccess(in_flight_fence_res, "Failed to create in-flight fence");
    }
}

fn drawFrame(
    allocator: std.mem.Allocator,
    logical_device: c.VkDevice,
    in_flight_fence_ptr: *c.VkFence,
    swapchain: *c.VkSwapchainKHR,
    image_available_semaphore: c.VkSemaphore,
    render_finished_semaphore: c.VkSemaphore,
    command_buffer: c.VkCommandBuffer,
    render_pass: c.VkRenderPass,
    swapchain_framebuffers: *[]c.VkFramebuffer,
    swapchain_extent: *c.VkExtent2D,
    swapchain_format: *c.VkFormat,
    graphics_pipeline: c.VkPipeline,
    graphics_queue: c.VkQueue,
    present_queue: c.VkQueue,
    surface: c.VkSurfaceKHR,
    window: *c.GLFWwindow,
    queue_family_indices: QueueFamilyIndices,
    physical_device: c.VkPhysicalDevice,
    swapchain_image_views: *[]c.VkImageView,
    swapchain_images: *[]c.VkImage,
) void {
    const wait_res = c.vkWaitForFences(logical_device, 1, in_flight_fence_ptr, c.VK_TRUE, std.math.maxInt(u64));
    fatalIfNotSuccess(wait_res, "Failed waiting for fences");

    var image_index: u32 = undefined;
    const acquire_image_res = c.vkAcquireNextImageKHR(
        logical_device,
        swapchain.*,
        std.math.maxInt(u64),
        image_available_semaphore,
        null,
        &image_index,
    );
    if (acquire_image_res == c.VK_ERROR_OUT_OF_DATE_KHR or acquire_image_res == c.VK_SUBOPTIMAL_KHR) {
        recreateSwapchain(
            allocator,
            surface,
            window,
            queue_family_indices,
            physical_device,
            logical_device,
            render_pass,
            RecreateSwapchainUpdatePointers{
                .swapchain = swapchain,
                .swapchain_format = swapchain_format,
                .swapchain_extent = swapchain_extent,
                .swapchain_image_views = swapchain_image_views,
                .swapchain_images = swapchain_images,
                .swapchain_framebuffers = swapchain_framebuffers,
            },
        );
        return; // if swapchain is incompatible then we have to do this, we could choose not to for the suboptimal case
    } else {
        fatalIfNotSuccess(acquire_image_res, "Failed to acquire next image");
    }

    const reset_fence_res = c.vkResetFences(logical_device, 1, in_flight_fence_ptr);
    fatalIfNotSuccess(reset_fence_res, "Failed to reset fences");

    const reset_buffer_res = c.vkResetCommandBuffer(command_buffer, 0);
    fatalIfNotSuccess(reset_buffer_res, "Failed to reset command buffer");

    recordCommandBuffer(
        command_buffer,
        image_index,
        render_pass,
        swapchain_framebuffers.*,
        swapchain_extent.*,
        graphics_pipeline,
    );

    const wait_semaphores = [_]c.VkSemaphore{image_available_semaphore};
    const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    const signal_semaphores = [_]c.VkSemaphore{render_finished_semaphore};
    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = wait_semaphores.len,
        .pWaitSemaphores = &wait_semaphores,
        .pWaitDstStageMask = &wait_stages,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer,
        .signalSemaphoreCount = signal_semaphores.len,
        .pSignalSemaphores = &signal_semaphores,
    };

    const submit_res = c.vkQueueSubmit(graphics_queue, 1, &submit_info, in_flight_fence_ptr.*);
    fatalIfNotSuccess(submit_res, "Failed to submit graphics queue");

    const swapchains = [_]c.VkSwapchainKHR{swapchain.*};
    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &signal_semaphores,
        .swapchainCount = swapchains.len,
        .pSwapchains = &swapchains,
        .pImageIndices = &image_index,
        .pResults = null,
    };

    const present_res = c.vkQueuePresentKHR(present_queue, &present_info);
    if (present_res == c.VK_ERROR_OUT_OF_DATE_KHR or present_res == c.VK_SUBOPTIMAL_KHR or framebuffer_resized) {
        framebuffer_resized = false;
        recreateSwapchain(
            allocator,
            surface,
            window,
            queue_family_indices,
            physical_device,
            logical_device,
            render_pass,
            RecreateSwapchainUpdatePointers{
                .swapchain = swapchain,
                .swapchain_format = swapchain_format,
                .swapchain_extent = swapchain_extent,
                .swapchain_image_views = swapchain_image_views,
                .swapchain_images = swapchain_images,
                .swapchain_framebuffers = swapchain_framebuffers,
            },
        );
        return; // if swapchain is incompatible then we have to do this, we could choose not to for the suboptimal case
    } else {
        fatalIfNotSuccess(present_res, "Failed to present image");
    }
}

const RecreateSwapchainUpdatePointers = struct {
    swapchain: *c.VkSwapchainKHR,
    swapchain_format: *c.VkFormat,
    swapchain_extent: *c.VkExtent2D,
    swapchain_image_views: *[]c.VkImageView,
    swapchain_images: *[]c.VkImage,
    swapchain_framebuffers: *[]c.VkFramebuffer,
};

fn recreateSwapchain(
    allocator: std.mem.Allocator,
    surface: c.VkSurfaceKHR,
    window: *c.GLFWwindow,
    queue_family_indices: QueueFamilyIndices,
    physical_device: c.VkPhysicalDevice,
    logical_device: c.VkDevice,
    render_pass: c.VkRenderPass,
    update_pointers: RecreateSwapchainUpdatePointers,
) void {
    var width: i32 = 0;
    var height: i32 = 0;
    c.glfwGetFramebufferSize(window, &width, &height);
    const window_minimised = width == 0 or height == 0;
    while (window_minimised) {
        c.glfwGetFramebufferSize(window, &width, &height);
        c.glfwWaitEvents();
    }

    const device_wait_res = c.vkDeviceWaitIdle(logical_device);
    fatalIfNotSuccess(device_wait_res, "Failed waiting for device idle");

    cleanupSwapchain(
        allocator,
        logical_device,
        update_pointers.swapchain_framebuffers.*,
        update_pointers.swapchain.*,
        update_pointers.swapchain_image_views.*,
        update_pointers.swapchain_images.*,
    );

    const create_swapchain_result = createSwapchain(
        allocator,
        surface,
        window,
        queue_family_indices,
        physical_device,
        logical_device,
    );
    const new_swapchain = create_swapchain_result.swapchain;
    const new_swapchain_format = create_swapchain_result.format;
    const new_swapchain_extent = create_swapchain_result.extent;

    const create_image_views_result = createImageViews(
        allocator,
        logical_device,
        new_swapchain,
        new_swapchain_format,
    );
    const new_image_views = create_image_views_result.swapchain_image_views;
    const new_images = create_image_views_result.swapchain_images;

    const new_framebuffers = createFramebuffers(
        allocator,
        new_image_views,
        render_pass,
        new_swapchain_extent,
        logical_device,
    );

    update_pointers.swapchain.* = new_swapchain;
    update_pointers.swapchain_format.* = new_swapchain_format;
    update_pointers.swapchain_extent.* = new_swapchain_extent;
    update_pointers.swapchain_images.* = new_images;
    update_pointers.swapchain_image_views.* = new_image_views;
    update_pointers.swapchain_framebuffers.* = new_framebuffers;
}

fn cleanupSwapchain(
    allocator: std.mem.Allocator,
    logical_device: c.VkDevice,
    swapchain_framebuffers: []c.VkFramebuffer,
    swapchain: c.VkSwapchainKHR,
    swapchain_image_views: []c.VkImageView,
    swapchain_images: []c.VkImage,
) void {
    for (swapchain_framebuffers) |fb| {
        c.vkDestroyFramebuffer(logical_device, fb, null);
    }
    for (swapchain_image_views) |image_view| {
        c.vkDestroyImageView(logical_device, image_view, null);
    }
    c.vkDestroySwapchainKHR(logical_device, swapchain, null);
    allocator.free(swapchain_image_views);
    allocator.free(swapchain_images);
    allocator.free(swapchain_framebuffers);
}

const Vertex = struct {
    pos: zlm.Vec2,
    color: zlm.Vec3,

    const Self = @This();

    fn getBindingDescription() c.VkVertexInputBindingDescription {
        return c.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(Self),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        };
    }

    fn getAttributeDescriptions() [2]c.VkVertexInputAttributeDescription {
        const positionAttributeDescription = c.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 0,
            .format = c.VK_FORMAT_R32G32_SFLOAT,
            .offset = @offsetOf(Vertex, "pos"),
        };
        const colorAttributeDescription = c.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 1,
            .format = c.VK_FORMAT_R32G32B32_SFLOAT,
            .offset = @offsetOf(Vertex, "color"),
        };
        return .{ positionAttributeDescription, colorAttributeDescription };
    }
};
