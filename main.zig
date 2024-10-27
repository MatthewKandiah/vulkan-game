const std = @import("std");
const linalg = @import("./linalg.zig");

const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", {});
    @cInclude("GLFW/glfw3.h");
    @cInclude("stb_image.h");
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
    Vertex.new(-0.5, -0.5, 1, 0, 0),
    Vertex.new(0.5, -0.5, 0, 1, 0),
    Vertex.new(0.5, 0.5, 0, 0, 1),
    Vertex.new(-0.5, 0.5, 1, 1, 1),
};

const indices = [_]u32{ 0, 1, 2, 2, 3, 0 };

const MAX_FRAMES_IN_FLIGHT = 2;

// nasty global state variable
// apparently not all Vulkan drivers emit expected events on window resize, this is a way to ensure we catch those cases too
var framebuffer_resized = false;
fn framebufferResizedCallback(_: *c.GLFWwindow, _: i32, _: i32) void {
    framebuffer_resized = true;
}

// TODO - createBuffer helper function
// TODO - createImage helper function

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // initialise GLFW window
    const glfw_init_res = c.glfwInit();
    if (glfw_init_res == c.GLFW_FALSE) {
        std.debug.print("init_res: {}\n", .{glfw_init_res});
        fatal("GLFW init failed");
    }
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API); // GLFW originally intended to create OpenGL context, this tells it not to
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_TRUE);
    const window = c.glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", null, null) orelse fatal("GLFW window creation failed");
    _ = c.glfwSetFramebufferSizeCallback(window, @ptrCast(&framebufferResizedCallback));

    // initialise Vulkan instance
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
    var supported_glfw_extension_count: u32 = 0;
    _ = c.vkEnumerateInstanceExtensionProperties(null, &supported_glfw_extension_count, null);
    const supported_glfw_extensions = allocator.alloc(c.VkExtensionProperties, supported_glfw_extension_count) catch fatalQuiet();
    defer allocator.free(supported_glfw_extensions);
    _ = c.vkEnumerateInstanceExtensionProperties(null, &supported_glfw_extension_count, supported_glfw_extensions.ptr);
    for (glfw_extensions[0..glfw_extension_count]) |glfw_x| {
        const len = std.mem.len(glfw_x);
        var found = false;
        for (supported_glfw_extensions) |x| {
            if (std.mem.eql(u8, glfw_x[0..len], x.extensionName[0..len])) {
                found = true;
                break;
            }
        }
        if (!found) {
            fatal("Unsupported extensions required");
        }
    }
    if (DEBUG) {
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
    const vulkan_instance_create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = glfw_extension_count,
        .ppEnabledExtensionNames = glfw_extensions,
        .enabledLayerCount = if (DEBUG) VALIDATION_LAYERS.len else 0,
        .ppEnabledLayerNames = if (DEBUG) @ptrCast(&VALIDATION_LAYERS) else null,
    };
    var vulkan_instance: c.VkInstance = undefined;
    const vulkan_instance_create_res = c.vkCreateInstance(&vulkan_instance_create_info, null, &vulkan_instance);
    fatalIfNotSuccess(vulkan_instance_create_res, "Failed to create Vulkan instance");

    // create surface
    var surface: c.VkSurfaceKHR = undefined;
    const surface_create_res = c.glfwCreateWindowSurface(vulkan_instance, window, null, &surface);
    fatalIfNotSuccess(surface_create_res, "Failed to create glfw surface");

    // pick a physical device
    var physical_device_count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(vulkan_instance, &physical_device_count, null);
    if (physical_device_count == 0) {
        fatal("Failed to find any GPUs with Vulkan support");
    }
    const physical_devices = allocator.alloc(c.VkPhysicalDevice, physical_device_count) catch fatalQuiet();
    defer allocator.free(physical_devices);
    _ = c.vkEnumeratePhysicalDevices(vulkan_instance, &physical_device_count, physical_devices.ptr);
    var best_physical_device: ?c.VkPhysicalDevice = null;
    var best_queue_family_indices: ?QueueFamilyIndices = null;
    for (physical_devices) |physical_device| {
        const extensions_supported = checkDeviceExtensionSupport(allocator, physical_device);
        const queue_family_indices = findQueueFamilies(allocator, physical_device, surface);
        if (queue_family_indices.isComplete() and extensions_supported) {
            var swapchain_capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
            _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &swapchain_capabilities);
            var surface_format_count: u32 = undefined;
            _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &surface_format_count, null);
            if (surface_format_count == 0) continue;
            var present_mode_count: u32 = undefined;
            _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, null);
            if (present_mode_count == 0) continue;
            var device_properties: c.VkPhysicalDeviceProperties = undefined;
            c.vkGetPhysicalDeviceProperties(physical_device, &device_properties);
            best_physical_device = physical_device;
            best_queue_family_indices = queue_family_indices;
            if (device_properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
                break; // prefer discrete GPUs
            }
        }
    }
    const physical_device = best_physical_device orelse fatal("Failed to find suitable physical devices");
    const queue_family_indices = best_queue_family_indices orelse fatal("Failed to find suitable queue family indices");

    // create logical device
    const graphics_queue_create_info = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = queue_family_indices.graphics_family.?,
        .queueCount = 1,
        .pQueuePriorities = &[_]f32{1},
    };
    const present_queue_create_info = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = queue_family_indices.present_family.?,
        .queueCount = 1,
        .pQueuePriorities = &[_]f32{1},
    };
    const queue_create_infos = [_]c.VkDeviceQueueCreateInfo{
        graphics_queue_create_info,
        present_queue_create_info,
    };
    const queue_create_info_count: u32 = if (queue_family_indices.graphics_family.? == queue_family_indices.present_family.?) 1 else 2;
    const physical_device_features = std.mem.zeroes(c.VkPhysicalDeviceFeatures);
    const device_create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queue_create_infos,
        .queueCreateInfoCount = queue_create_info_count,
        .pEnabledFeatures = &physical_device_features,
        .enabledExtensionCount = DEVICE_EXTENSIONS.len,
        .ppEnabledExtensionNames = @ptrCast(&DEVICE_EXTENSIONS),
        .enabledLayerCount = 0,
    };
    var logical_device: c.VkDevice = undefined;
    const res = c.vkCreateDevice(physical_device, &device_create_info, null, &logical_device);
    fatalIfNotSuccess(res, "Failed to create logical device");

    // create swapchain
    const swapchain_info = createSwapchain(
        allocator,
        surface,
        window,
        queue_family_indices,
        physical_device,
        logical_device,
    );
    var swapchain = swapchain_info.swapchain.?;
    var swapchain_image_format = swapchain_info.format;
    var swapchain_extent = swapchain_info.extent;

    // create swapchain images and swapchain image views
    const swapchain_images_and_image_views = createImageViews(
        allocator,
        logical_device,
        swapchain,
        swapchain_image_format,
    );
    var swapchain_image_views = swapchain_images_and_image_views.image_views;
    var swapchain_images = swapchain_images_and_image_views.images;

    // create queues
    var graphics_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(logical_device, queue_family_indices.graphics_family.?, 0, &graphics_queue);
    var present_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(logical_device, queue_family_indices.present_family.?, 0, &present_queue);

    // create render pass
    const color_attachment = c.VkAttachmentDescription{
        .format = swapchain_image_format,
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

    // create and bind descriptor set layout
    const ubo_descriptor_set_layout_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
        .pImmutableSamplers = null,
    };
    var ubo_descriptor_set_layout: c.VkDescriptorSetLayout = undefined;
    const ubo_descriptor_set_layout_create_info = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &ubo_descriptor_set_layout_binding,
    };
    const ubo_descriptor_set_layout_create_res = c.vkCreateDescriptorSetLayout(logical_device, &ubo_descriptor_set_layout_create_info, null, &ubo_descriptor_set_layout);
    fatalIfNotSuccess(ubo_descriptor_set_layout_create_res, "Failed to create descriptor set layout");

    // create graphics pipeline
    const vert_shader_module = createShaderModule(VERT_SHADER_RAW, logical_device);
    const frag_shader_module = createShaderModule(FRAG_SHADER_RAW, logical_device);
    const vert_pipeline_shader_stage_create_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vert_shader_module,
        .pName = "main",
        .pNext = null,
        .pSpecializationInfo = null,
        .flags = 0,
    };
    const frag_pipeline_shader_stage_create_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = frag_shader_module,
        .pName = "main",
        .pNext = null,
        .pSpecializationInfo = null,
        .flags = 0,
    };
    const pipeline_shader_stages_create_info = [_]c.VkPipelineShaderStageCreateInfo{ vert_pipeline_shader_stage_create_info, frag_pipeline_shader_stage_create_info };
    const dynamic_states = [_]c.VkDynamicState{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
    const pipeline_dynamic_state_create_info = c.VkPipelineDynamicStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamic_states.len,
        .pDynamicStates = &dynamic_states,
        .pNext = null,
        .flags = 0,
    };
    const binding_description = Vertex.getBindingDescription();
    const attribute_descriptions = Vertex.getAttributeDescriptions();
    const pipeline_vertex_input_create_info = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &binding_description,
        .vertexAttributeDescriptionCount = attribute_descriptions.len,
        .pVertexAttributeDescriptions = &attribute_descriptions,
    };
    const pipeline_input_assembly_create_info = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
        .pNext = null,
        .flags = 0,
    };
    // viewports and scissors don't have to be set here because we're setting them dynamically at drawing time
    const pipeline_viewport_state_create_info = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };
    // NOTE - diverged from tutorial here, they have to switch their frontFace to counter clockwise
    const pipeline_rasterization_state_create_info = c.VkPipelineRasterizationStateCreateInfo{
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
    const pipeline_multisample_state_create_info = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = c.VK_FALSE,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        .minSampleShading = 1,
        .pSampleMask = null,
        .alphaToCoverageEnable = c.VK_FALSE,
        .alphaToOneEnable = c.VK_FALSE,
    };
    const pipeline_color_blend_attachment_state = c.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = c.VK_FALSE,
    };
    const pipeline_color_blend_state_create_info = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = c.VK_FALSE,
        .attachmentCount = 1,
        .pAttachments = &pipeline_color_blend_attachment_state,
    };
    var pipeline_layout: c.VkPipelineLayout = undefined;
    const pipeline_layout_create_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &ubo_descriptor_set_layout,
    };
    const pipeline_layout_create_res = c.vkCreatePipelineLayout(logical_device, &pipeline_layout_create_info, null, &pipeline_layout);
    fatalIfNotSuccess(pipeline_layout_create_res, "Failed to create pipeline layout");
    const pipeline_create_info = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = &pipeline_shader_stages_create_info,
        .pVertexInputState = &pipeline_vertex_input_create_info,
        .pInputAssemblyState = &pipeline_input_assembly_create_info,
        .pViewportState = &pipeline_viewport_state_create_info,
        .pRasterizationState = &pipeline_rasterization_state_create_info,
        .pMultisampleState = &pipeline_multisample_state_create_info,
        .pDepthStencilState = null,
        .pColorBlendState = &pipeline_color_blend_state_create_info,
        .pDynamicState = &pipeline_dynamic_state_create_info,
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

    // create framebuffers
    var swapchain_framebuffers = createFramebuffers(
        allocator,
        swapchain_image_views,
        render_pass,
        swapchain_extent,
        logical_device,
    );

    // create command pool
    const pool_create_info = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queue_family_indices.graphics_family.?,
    };
    var command_pool: c.VkCommandPool = undefined;
    const pool_create_res = c.vkCreateCommandPool(logical_device, &pool_create_info, null, &command_pool);
    fatalIfNotSuccess(pool_create_res, "Failed to create command pool");

    // create texture image staging buffer
    var tex_width: i32 = undefined;
    var tex_height: i32 = undefined;
    var tex_channels: i32 = undefined;
    const tex_pixels = c.stbi_load(
        "textures/texture.jpg",
        &tex_width,
        &tex_height,
        &tex_channels,
        c.STBI_rgb_alpha,
    );
    if (tex_pixels == 0) {
        fatal("Failed to load texture image");
    }
    const tex_image_size = tex_width * tex_height * 4;
    var tex_staging_buffer: c.VkBuffer = undefined;
    var tex_staging_buffer_memory: c.VkDeviceMemory = undefined;
    const create_tex_staging_buffer_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = @intCast(tex_image_size),
        .usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    };
    const create_tex_staging_buffer_res = c.vkCreateBuffer(logical_device, &create_tex_staging_buffer_info, null, &tex_staging_buffer);
    fatalIfNotSuccess(create_tex_staging_buffer_res, "Failed to create texture staging buffer");
    var tex_staging_buffer_mem_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(logical_device, tex_staging_buffer, &tex_staging_buffer_mem_requirements);
    const tex_staging_buffer_alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = tex_staging_buffer_mem_requirements.size,
        .memoryTypeIndex = findMemoryType(
            physical_device,
            tex_staging_buffer_mem_requirements.memoryTypeBits,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        ),
    };
    const tex_staging_buffer_alloc_res = c.vkAllocateMemory(logical_device, &tex_staging_buffer_alloc_info, null, &tex_staging_buffer_memory);
    fatalIfNotSuccess(tex_staging_buffer_alloc_res, "Failed to allocated texture staging buffer memory");
    const bind_tex_staging_buffer_memory_res = c.vkBindBufferMemory(logical_device, tex_staging_buffer, tex_staging_buffer_memory, 0);
    fatalIfNotSuccess(bind_tex_staging_buffer_memory_res, "Failed to bind texture staging buffer memory");

    // copy image data into texture staging buffer
    var tex_image_data: *anyopaque = undefined;
    const tex_image_map_memory_res = c.vkMapMemory(
        logical_device,
        tex_staging_buffer_memory,
        0,
        @intCast(tex_image_size),
        0,
        @alignCast(@ptrCast(&tex_image_data)),
    );
    fatalIfNotSuccess(tex_image_map_memory_res, "Failed to map texture image memory");
    std.mem.copyForwards(u8, @as([*]u8, @alignCast(@ptrCast(tex_image_data)))[0..@intCast(tex_image_size)], tex_pixels[0..@intCast(tex_image_size)]);
    c.vkUnmapMemory(logical_device, tex_staging_buffer_memory);
    c.stbi_image_free(tex_pixels);

    // create texture image
    var texture_image: c.VkImage = undefined;
    var texture_image_memory: c.VkDeviceMemory = undefined;
    const create_texture_image_info = c.VkImageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_VIEW_TYPE_2D,
        .extent = .{ .width = @intCast(tex_width), .height = @intCast(tex_height), .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .format = c.VK_FORMAT_R8G8B8A8_SRGB,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .usage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .flags = 0,
    };
    const create_texture_image_res = c.vkCreateImage(logical_device, &create_texture_image_info, null, &texture_image);
    fatalIfNotSuccess(create_texture_image_res, "Failed to create texture image");
    var texture_image_mem_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(logical_device, texture_image, &texture_image_mem_requirements);
    const texture_image_alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = texture_image_mem_requirements.size,
        .memoryTypeIndex = findMemoryType(
            physical_device,
            texture_image_mem_requirements.memoryTypeBits,
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        ),
    };
    const texture_image_alloc_res = c.vkAllocateMemory(logical_device, &texture_image_alloc_info, null, &texture_image_memory);
    fatalIfNotSuccess(texture_image_alloc_res, "Failed to allocate image memory");
    const texture_image_memory_bind_res = c.vkBindImageMemory(logical_device, texture_image, texture_image_memory, 0);
    fatalIfNotSuccess(texture_image_memory_bind_res, "Failed to bind image memory");

    // create vertex staging buffer
    const vertex_buffer_size: u64 = @sizeOf(Vertex) * vertices.len;
    var vertex_staging_buffer: c.VkBuffer = undefined;
    const create_vertex_staging_buffer_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = vertex_buffer_size,
        .usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    };
    const create_vertex_staging_buffer_res = c.vkCreateBuffer(logical_device, &create_vertex_staging_buffer_info, null, &vertex_staging_buffer);
    fatalIfNotSuccess(create_vertex_staging_buffer_res, "Failed to create staging buffer");
    var vertex_staging_buffer_mem_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(logical_device, vertex_staging_buffer, &vertex_staging_buffer_mem_requirements);
    var vertex_staging_buffer_memory: c.VkDeviceMemory = undefined;
    const vertex_staging_buffer_alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = vertex_staging_buffer_mem_requirements.size,
        .memoryTypeIndex = findMemoryType(
            physical_device,
            vertex_staging_buffer_mem_requirements.memoryTypeBits,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        ),
    };
    const vertex_staging_buffer_alloc_res = c.vkAllocateMemory(logical_device, &vertex_staging_buffer_alloc_info, null, &vertex_staging_buffer_memory);
    fatalIfNotSuccess(vertex_staging_buffer_alloc_res, "Failed to allocate staging buffer memory");
    const bind_vertex_staging_buffer_memory_res = c.vkBindBufferMemory(logical_device, vertex_staging_buffer, vertex_staging_buffer_memory, 0);
    fatalIfNotSuccess(bind_vertex_staging_buffer_memory_res, "Failed to bind staging buffer memory");

    // create vertex buffer
    var vertex_buffer: c.VkBuffer = undefined;
    const create_vertex_buffer_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = vertex_buffer_size,
        .usage = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    };
    const create_vertex_buffer_res = c.vkCreateBuffer(logical_device, &create_vertex_buffer_info, null, &vertex_buffer);
    fatalIfNotSuccess(create_vertex_buffer_res, "Failed to create vertex buffer");
    var vertex_buffer_mem_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(logical_device, vertex_buffer, &vertex_buffer_mem_requirements);
    var vertex_buffer_memory: c.VkDeviceMemory = undefined;
    const vertex_buffer_alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = vertex_buffer_mem_requirements.size,
        .memoryTypeIndex = findMemoryType(
            physical_device,
            vertex_buffer_mem_requirements.memoryTypeBits,
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        ),
    };
    const vertex_buffer_alloc_res = c.vkAllocateMemory(logical_device, &vertex_buffer_alloc_info, null, &vertex_buffer_memory);
    fatalIfNotSuccess(vertex_buffer_alloc_res, "Failed to allocate vertex buffer memory");
    const bind_vertex_buffer_memory_res = c.vkBindBufferMemory(logical_device, vertex_buffer, vertex_buffer_memory, 0);
    fatalIfNotSuccess(bind_vertex_buffer_memory_res, "Failed to bind vertex buffer memory");

    // copy data from vertex staging buffer to vertex buffer
    var data: *anyopaque = undefined;
    const map_memory_res = c.vkMapMemory(
        logical_device,
        vertex_staging_buffer_memory,
        0,
        vertex_buffer_size,
        0,
        @ptrCast(&data),
    );
    fatalIfNotSuccess(map_memory_res, "Failed map memory");
    std.mem.copyForwards(Vertex, @as([*]Vertex, @alignCast(@ptrCast(data)))[0..vertices.len], &vertices);
    c.vkUnmapMemory(logical_device, vertex_staging_buffer_memory);
    copyBuffer(
        logical_device,
        command_pool,
        graphics_queue,
        vertex_staging_buffer,
        vertex_buffer,
        vertex_buffer_size,
    );
    c.vkDestroyBuffer(logical_device, vertex_staging_buffer, null);
    c.vkFreeMemory(logical_device, vertex_staging_buffer_memory, null);

    // create index staging buffer
    const index_buffer_size = @sizeOf(@TypeOf(indices[0])) * indices.len;
    var index_staging_buffer: c.VkBuffer = undefined;
    const create_index_staging_buffer_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = vertex_buffer_size,
        .usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    };
    const create_index_staging_buffer_res = c.vkCreateBuffer(logical_device, &create_index_staging_buffer_info, null, &index_staging_buffer);
    fatalIfNotSuccess(create_index_staging_buffer_res, "Failed to create staging buffer");
    var index_staging_buffer_mem_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(logical_device, index_staging_buffer, &index_staging_buffer_mem_requirements);
    var index_staging_buffer_memory: c.VkDeviceMemory = undefined;
    const index_staging_buffer_alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = index_staging_buffer_mem_requirements.size,
        .memoryTypeIndex = findMemoryType(
            physical_device,
            index_staging_buffer_mem_requirements.memoryTypeBits,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        ),
    };
    const index_staging_buffer_alloc_res = c.vkAllocateMemory(logical_device, &index_staging_buffer_alloc_info, null, &index_staging_buffer_memory);
    fatalIfNotSuccess(index_staging_buffer_alloc_res, "Failed to allocate staging buffer memory");
    const bind_index_staging_buffer_memory_res = c.vkBindBufferMemory(logical_device, index_staging_buffer, index_staging_buffer_memory, 0);
    fatalIfNotSuccess(bind_index_staging_buffer_memory_res, "Failed to bind staging buffer memory");

    // create index buffer
    var index_buffer: c.VkBuffer = undefined;
    const create_index_buffer_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = index_buffer_size,
        .usage = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    };
    const create_index_buffer_res = c.vkCreateBuffer(logical_device, &create_index_buffer_info, null, &index_buffer);
    fatalIfNotSuccess(create_index_buffer_res, "Failed to create indices buffer");
    var index_buffer_mem_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(logical_device, index_buffer, &index_buffer_mem_requirements);
    var index_buffer_memory: c.VkDeviceMemory = undefined;
    const index_buffer_alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = index_buffer_mem_requirements.size,
        .memoryTypeIndex = findMemoryType(
            physical_device,
            index_buffer_mem_requirements.memoryTypeBits,
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        ),
    };
    const index_buffer_alloc_res = c.vkAllocateMemory(logical_device, &index_buffer_alloc_info, null, &index_buffer_memory);
    fatalIfNotSuccess(index_buffer_alloc_res, "Failed to allocate indices buffer memory");
    const bind_index_buffer_memory_res = c.vkBindBufferMemory(logical_device, index_buffer, index_buffer_memory, 0);
    fatalIfNotSuccess(bind_index_buffer_memory_res, "Failed to bind indices buffer memory");

    const index_map_memory_res = c.vkMapMemory(
        logical_device,
        index_staging_buffer_memory,
        0,
        index_buffer_size,
        0,
        @ptrCast(&data),
    );
    fatalIfNotSuccess(index_map_memory_res, "Failed map memory");
    std.mem.copyForwards(u32, @as([*]u32, @alignCast(@ptrCast(data)))[0..indices.len], &indices);
    c.vkUnmapMemory(logical_device, index_staging_buffer_memory);

    // copy index staging buffer to index buffer
    copyBuffer(
        logical_device,
        command_pool,
        graphics_queue,
        index_staging_buffer,
        index_buffer,
        index_buffer_size,
    );
    c.vkDestroyBuffer(logical_device, index_staging_buffer, null);
    c.vkFreeMemory(logical_device, index_staging_buffer_memory, null);

    // create uniform buffers
    const uniform_buffer_size = @sizeOf(UniformBufferObject);
    var uniform_buffers: [MAX_FRAMES_IN_FLIGHT]c.VkBuffer = undefined;
    var uniform_buffers_memory: [MAX_FRAMES_IN_FLIGHT]c.VkDeviceMemory = undefined;
    var uniform_buffers_mapped: [MAX_FRAMES_IN_FLIGHT]*anyopaque = undefined;
    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        const create_uniform_buffer_info = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = uniform_buffer_size,
            .usage = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        };
        const create_uniform_buffer_res = c.vkCreateBuffer(logical_device, &create_uniform_buffer_info, null, &uniform_buffers[i]);
        fatalIfNotSuccess(create_uniform_buffer_res, "Failed to create uniform buffer");
        var uniform_buffer_mem_requirements: c.VkMemoryRequirements = undefined;
        c.vkGetBufferMemoryRequirements(logical_device, uniform_buffers[i], &uniform_buffer_mem_requirements);
        const uniform_buffer_alloc_info = c.VkMemoryAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = uniform_buffer_mem_requirements.size,
            .memoryTypeIndex = findMemoryType(
                physical_device,
                uniform_buffer_mem_requirements.memoryTypeBits,
                c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            ),
        };
        const uniform_buffer_alloc_res = c.vkAllocateMemory(logical_device, &uniform_buffer_alloc_info, null, &uniform_buffers_memory[i]);
        fatalIfNotSuccess(uniform_buffer_alloc_res, "Failed to allocate uniform buffer memory");
        const bind_uniform_buffer_memory_res = c.vkBindBufferMemory(logical_device, uniform_buffers[i], uniform_buffers_memory[i], 0);
        fatalIfNotSuccess(bind_uniform_buffer_memory_res, "Failed to bind uniform buffer memory");
        // Note - persistent mapping, by keeping these pointers for the application's lifetime we can write data to it whenever we need to
        const uniform_map_memory_res = c.vkMapMemory(
            logical_device,
            uniform_buffers_memory[i],
            0,
            uniform_buffer_size,
            0,
            @ptrCast(&uniform_buffers_mapped[i]),
        );
        fatalIfNotSuccess(uniform_map_memory_res, "Failed to map uniform memory");
    }

    // create descriptor pool
    const descriptor_pool_size = c.VkDescriptorPoolSize{
        .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = MAX_FRAMES_IN_FLIGHT,
    };
    const descriptor_pool_create_info = c.VkDescriptorPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = 1,
        .pPoolSizes = &descriptor_pool_size,
        .maxSets = MAX_FRAMES_IN_FLIGHT,
    };
    var descriptor_pool: c.VkDescriptorPool = undefined;
    const descriptor_pool_create_res = c.vkCreateDescriptorPool(logical_device, &descriptor_pool_create_info, null, &descriptor_pool);
    fatalIfNotSuccess(descriptor_pool_create_res, "Failed to create descriptor pool");

    // create descriptor sets
    const descriptor_set_layouts = [MAX_FRAMES_IN_FLIGHT]c.VkDescriptorSetLayout{ ubo_descriptor_set_layout, ubo_descriptor_set_layout };
    const descriptor_set_allocate_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = descriptor_pool,
        .descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
        .pSetLayouts = &descriptor_set_layouts,
    };
    var descriptor_sets: [MAX_FRAMES_IN_FLIGHT]c.VkDescriptorSet = undefined;
    const descriptor_sets_allocate_res = c.vkAllocateDescriptorSets(logical_device, &descriptor_set_allocate_info, &descriptor_sets);
    fatalIfNotSuccess(descriptor_sets_allocate_res, "Failed to allocate descriptor sets");
    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        const descriptor_buffer_info = c.VkDescriptorBufferInfo{
            .buffer = uniform_buffers[i],
            .offset = 0,
            .range = @sizeOf(UniformBufferObject),
        };
        const write_descriptor_set = c.VkWriteDescriptorSet{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = descriptor_sets[i],
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1,
            .pBufferInfo = &descriptor_buffer_info,
        };
        c.vkUpdateDescriptorSets(logical_device, 1, &write_descriptor_set, 0, null);
    }

    // create command buffers
    const command_buffer_alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = MAX_FRAMES_IN_FLIGHT,
    };
    var command_buffers: [MAX_FRAMES_IN_FLIGHT]c.VkCommandBuffer = undefined;
    const command_buffers_alloc_res = c.vkAllocateCommandBuffers(logical_device, &command_buffer_alloc_info, &command_buffers);
    fatalIfNotSuccess(command_buffers_alloc_res, "Failed to allocate command buffers");

    // create synchronisation objects
    var image_available_semaphores: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = undefined;
    var render_finished_semaphores: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = undefined;
    var in_flight_fences: [MAX_FRAMES_IN_FLIGHT]c.VkFence = undefined;
    const semaphore_create_info = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    const fence_create_info = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        const image_available_semaphore_res = c.vkCreateSemaphore(logical_device, &semaphore_create_info, null, &image_available_semaphores[i]);
        fatalIfNotSuccess(image_available_semaphore_res, "Failed to create image available semaphore");

        const render_finished_semaphore_res = c.vkCreateSemaphore(logical_device, &semaphore_create_info, null, &render_finished_semaphores[i]);
        fatalIfNotSuccess(render_finished_semaphore_res, "Failed to create render finished semaphore");

        const in_flight_fence_res = c.vkCreateFence(logical_device, &fence_create_info, null, &in_flight_fences[i]);
        fatalIfNotSuccess(in_flight_fence_res, "Failed to create in-flight fence");
    }

    var current_frame_index: u32 = 0;
    const start_time_millis = std.time.milliTimestamp();
    // main loop
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
            vertex_buffer,
            index_buffer,
            uniform_buffers_mapped[current_frame_index],
            start_time_millis,
            &descriptor_sets[current_frame_index],
            pipeline_layout,
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
    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        c.vkDestroyBuffer(logical_device, uniform_buffers[i], null);
        c.vkFreeMemory(logical_device, uniform_buffers_memory[i], null);
    }
    c.vkDestroyDescriptorPool(logical_device, descriptor_pool, null);
    c.vkDestroyDescriptorSetLayout(logical_device, ubo_descriptor_set_layout, null);
    c.vkDestroyBuffer(logical_device, vertex_buffer, null);
    c.vkFreeMemory(logical_device, vertex_buffer_memory, null);
    c.vkDestroyBuffer(logical_device, index_buffer, null);
    c.vkFreeMemory(logical_device, index_buffer_memory, null);
    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        c.vkDestroySemaphore(logical_device, image_available_semaphores[i], null);
        c.vkDestroySemaphore(logical_device, render_finished_semaphores[i], null);
        c.vkDestroyFence(logical_device, in_flight_fences[i], null);
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

const QueueFamilyIndices = struct {
    graphics_family: ?u32,
    present_family: ?u32,

    const Self = @This();

    fn isComplete(self: Self) bool {
        return self.graphics_family != null and self.present_family != null;
    }
};

fn findQueueFamilies(allocator: std.mem.Allocator, device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) QueueFamilyIndices {
    var queue_family_count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);
    const queue_families = allocator.alloc(c.VkQueueFamilyProperties, queue_family_count) catch fatalQuiet();
    defer allocator.free(queue_families);
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);
    var valid_graphics_family: ?u32 = null;
    var valid_present_family: ?u32 = null;
    for (queue_families, 0..) |qf, i| {
        const does_support_graphics = qf.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0;
        var present_support: u32 = c.VK_FALSE;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface, &present_support);
        const does_support_present = present_support != c.VK_FALSE;
        // if one queue family supports all our requirements, it's best to use it
        if (does_support_graphics and does_support_present) {
            return QueueFamilyIndices{
                .graphics_family = @intCast(i),
                .present_family = @intCast(i),
            };
        }
        if (qf.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            valid_graphics_family = @intCast(i);
        }
        if (present_support != c.VK_FALSE) {
            valid_present_family = @intCast(i);
        }
    }
    return QueueFamilyIndices{
        .graphics_family = valid_graphics_family,
        .present_family = valid_present_family,
    };
}

const SwapchainInfo = struct {
    swapchain: c.VkSwapchainKHR,
    format: c.VkFormat,
    extent: c.VkExtent2D,
};

// used for both creating the swapchain initially, and recreating it when the old swapchain is invalid/not optimal
fn createSwapchain(
    allocator: std.mem.Allocator,
    surface: c.VkSurfaceKHR,
    window: *c.GLFWwindow,
    queue_family_indices: QueueFamilyIndices,
    physical_device: c.VkPhysicalDevice,
    logical_device: c.VkDevice,
) SwapchainInfo {
    // get all the values the physical device supports
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

    // choose which supported values we want to use
    const swapchain_surface_format = chooseSwapSurfaceFormat(swapchain_surface_formats);
    const swapchain_present_mode = chooseSwapPresentMode(swapchain_present_modes);
    const swapchain_extent = chooseSwapExtent(window, swapchain_capabilities);
    allocator.free(swapchain_surface_formats);
    allocator.free(swapchain_present_modes);
    var swapchain_image_count: u32 = swapchain_capabilities.minImageCount + 1;
    if (swapchain_capabilities.maxImageCount > 0 and swapchain_image_count > swapchain_capabilities.maxImageCount) {
        swapchain_image_count = swapchain_capabilities.maxImageCount;
    }

    // create swapchain
    var swapchain_create_info: c.VkSwapchainCreateInfoKHR = .{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = swapchain_image_count,
        .imageFormat = swapchain_surface_format.format,
        .imageColorSpace = swapchain_surface_format.colorSpace,
        .imageExtent = swapchain_extent,
        .imageArrayLayers = 1,
        // NOTE - this imageUsage is used to render an image directly to the screen
        //        if you want to perform post-processing you will want to render to another image first
        //        in that case consider using c.VK_IMAGE_USAGE_TRANSFER_DST_BIT and a memory operation
        //        to transfer the rendered image to a swapchain image
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .preTransform = swapchain_capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = swapchain_present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = @ptrCast(c.VK_NULL_HANDLE),
    };
    if (queue_family_indices.graphics_family != queue_family_indices.present_family) {
        swapchain_create_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        swapchain_create_info.queueFamilyIndexCount = 2;
        swapchain_create_info.pQueueFamilyIndices = &[2]u32{ queue_family_indices.graphics_family.?, queue_family_indices.present_family.? };
    } else {
        swapchain_create_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        swapchain_create_info.queueFamilyIndexCount = 0;
        swapchain_create_info.pQueueFamilyIndices = null;
    }
    var swapchain: c.VkSwapchainKHR = undefined;
    const create_swapchain_res = c.vkCreateSwapchainKHR(logical_device, &swapchain_create_info, null, &swapchain);
    fatalIfNotSuccess(create_swapchain_res, "Failed to create swapchain");
    return SwapchainInfo{
        .swapchain = swapchain,
        .extent = swapchain_extent,
        .format = swapchain_surface_format.format,
    };
}

const ImagesAndImageViews = struct {
    image_views: []c.VkImageView,
    images: []c.VkImage,
};

fn createImageViews(
    allocator: std.mem.Allocator,
    logical_device: c.VkDevice,
    swapchain: c.VkSwapchainKHR,
    swapchain_image_format: c.VkFormat,
) ImagesAndImageViews {
    // create swapchain images
    var swapchain_image_count: u32 = undefined;
    _ = c.vkGetSwapchainImagesKHR(logical_device, swapchain, &swapchain_image_count, null);
    const swapchain_images = allocator.alloc(c.VkImage, swapchain_image_count) catch fatalQuiet();
    _ = c.vkGetSwapchainImagesKHR(logical_device, swapchain, &swapchain_image_count, swapchain_images.ptr);

    // create swapchain image views
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
    return ImagesAndImageViews{
        .image_views = swapchain_image_views,
        .images = swapchain_images,
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

fn createShaderModule(comptime shader: []const u8, logical_device: c.VkDevice) c.VkShaderModule {
    // NOTE - this smells very system dependent
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
    vertex_buffer: c.VkBuffer,
    index_buffer: c.VkBuffer,
    uniform_buffer_mapped: *anyopaque,
    start_time: i64,
    descriptor_set: *c.VkDescriptorSet,
    pipeline_layout: c.VkPipelineLayout,
) void {
    // before we start drawing this frame, we want to wait until the previous frame has finished drawing, or state will bleed from one frame into the next
    const wait_res = c.vkWaitForFences(logical_device, 1, in_flight_fence_ptr, c.VK_TRUE, std.math.maxInt(u64));
    fatalIfNotSuccess(wait_res, "Failed waiting for fences");

    // get the next image in the swapchain that we're going to write to
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

    // If we don't reset the fence now, then the next call to drawFrame won't wait at the start as expected
    const reset_fence_res = c.vkResetFences(logical_device, 1, in_flight_fence_ptr);
    fatalIfNotSuccess(reset_fence_res, "Failed to reset fences");

    // clear the command buffer so previous frame commands are gone
    const reset_command_buffer_res = c.vkResetCommandBuffer(command_buffer, 0);
    fatalIfNotSuccess(reset_command_buffer_res, "Failed to reset command buffer");

    // start recording commands into command buffer
    const begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    };
    const begin_res = c.vkBeginCommandBuffer(command_buffer, &begin_info);
    fatalIfNotSuccess(begin_res, "Failed to begin recording command buffer");

    // clear to opaque black
    const clear_color = c.VkClearValue{
        .color = .{ .float32 = .{ 0, 0, 0, 1 } },
    };

    // start render pass - we're about to start processing graphics commands
    const render_pass_info = c.VkRenderPassBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = render_pass,
        .framebuffer = swapchain_framebuffers.*[image_index],
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = swapchain_extent.*,
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
    const vertex_buffers = [_]c.VkBuffer{vertex_buffer};
    const offsets = [_]u64{0};
    c.vkCmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffers, &offsets);
    c.vkCmdBindIndexBuffer(command_buffer, index_buffer, 0, c.VK_INDEX_TYPE_UINT32);

    // set dynamic state values
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
        .extent = swapchain_extent.*,
    };
    c.vkCmdSetScissor(command_buffer, 0, 1, &scissor);

    // a descriptor is an opaque data structure representing a shader resource (e.g. a buffer, image view, sampler, etc.)
    // descriptors are orgnanised into descriptor sets, this is literally just one or more descriptors stored in an opaque object
    // binding the descriptor set just means it will be used in the subsequent draw commands
    c.vkCmdBindDescriptorSets(
        command_buffer,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        pipeline_layout,
        0,
        1,
        descriptor_set,
        0,
        null,
    );

    // actually update the image data in the current swapchain
    c.vkCmdDrawIndexed(command_buffer, indices.len, 1, 0, 0, 0);

    // finish the render pass - we're done processing graphics commands
    c.vkCmdEndRenderPass(command_buffer);

    // finish writing to command buffer
    const end_command_buffer_res = c.vkEndCommandBuffer(command_buffer);
    fatalIfNotSuccess(end_command_buffer_res, "Failed to end command buffer");

    // use time elapsed to get a different angle for each frame
    const current_time_millis = std.time.milliTimestamp();
    const time_millis = current_time_millis - start_time;
    const angle: f32 = @as(f32, @floatFromInt(time_millis)) / 500;
    const ubo = UniformBufferObject{
        // rotation in the x-y plane
        .model = linalg.Mat4(f32).new(
            linalg.Vec4(f32).new(@cos(angle), @sin(angle), 0, 0),
            linalg.Vec4(f32).new(-@sin(angle), @cos(angle), 0, 0),
            linalg.Vec4(f32).new(0, 0, 1, 0),
            linalg.Vec4(f32).new(0, 0, 0, 1),
        ),
        // move the space forward == move the camera back
        .view = linalg.Mat4(f32).new(
            linalg.Vec4(f32).new(1, 0, 0, 0),
            linalg.Vec4(f32).new(0, 1, 0, 0),
            linalg.Vec4(f32).new(0, 0, 1, -2),
            linalg.Vec4(f32).new(0, 0, 0, 1),
        ),
        // simple projection
        .proj = linalg.Mat4(f32).new(
            linalg.Vec4(f32).new(1, 0, 0, 0),
            linalg.Vec4(f32).new(0, 1, 0, 0),
            linalg.Vec4(f32).new(0, 0, 0, 0),
            linalg.Vec4(f32).new(0, 0, 0, 1),
        ),
    };
    std.mem.copyForwards(UniformBufferObject, @as([*]UniformBufferObject, @alignCast(@ptrCast(uniform_buffer_mapped)))[0..1], &.{ubo});

    // submit our commands - ask the GPU to draw to our current swapchain image, ready to show this frame on screen
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

    // show the current image on screen, but only once the GPU has finished writing the current frame's image data
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
    const swapchain_info = createSwapchain(
        allocator,
        surface,
        window,
        queue_family_indices,
        physical_device,
        logical_device,
    );
    const new_swapchain = swapchain_info.swapchain;
    const new_swapchain_format = swapchain_info.format;
    const new_swapchain_extent = swapchain_info.extent;
    const swapchain_images_and_image_views = createImageViews(
        allocator,
        logical_device,
        new_swapchain,
        new_swapchain_format,
    );
    const new_image_views = swapchain_images_and_image_views.image_views;
    const new_images = swapchain_images_and_image_views.images;
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

fn findMemoryType(physical_device: c.VkPhysicalDevice, type_filter: u32, properties: c.VkMemoryPropertyFlags) u32 {
    var mem_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
    c.vkGetPhysicalDeviceMemoryProperties(physical_device, &mem_properties);
    for (0..mem_properties.memoryTypeCount) |i| {
        if (type_filter & (@as(u32, 1) << @intCast(i)) != 0 and mem_properties.memoryTypes[i].propertyFlags & properties == properties) {
            return @intCast(i);
        }
    }
    fatal("Failed to find suitable memory type");
}

fn beginSingleTimeCommands(logical_device: c.VkDevice, command_pool: c.VkCommandPool) c.VkCommandBuffer {
    const command_buffer_alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandPool = command_pool,
        .commandBufferCount = 1,
    };
    var command_buffer: c.VkCommandBuffer = undefined;
    const command_buffer_alloc_res = c.vkAllocateCommandBuffers(logical_device, &command_buffer_alloc_info, &command_buffer);
    fatalIfNotSuccess(command_buffer_alloc_res, "Failed to allocate single use command buffer");

    const command_buffer_begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };

    const begin_command_buffer_res = c.vkBeginCommandBuffer(command_buffer, &command_buffer_begin_info);
    fatalIfNotSuccess(begin_command_buffer_res, "Failed to begin single use command buffer");

    return command_buffer;
}

fn endSingleTimeCommands(
    logical_device: c.VkDevice,
    command_pool: c.VkCommandPool,
    graphics_queue: c.VkQueue,
    command_buffer: c.VkCommandBuffer,
) void {
    const end_command_buffer_res = c.vkEndCommandBuffer(command_buffer);
    fatalIfNotSuccess(end_command_buffer_res, "Failed to end single use command buffer");

    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer,
    };
    const submit_res = c.vkQueueSubmit(graphics_queue, 1, &submit_info, null);
    fatalIfNotSuccess(submit_res, "Failed to submit single use command buffer");

    const wait_res = c.vkQueueWaitIdle(graphics_queue);
    fatalIfNotSuccess(wait_res, "Failed to wait for graphics queue idle");

    c.vkFreeCommandBuffers(logical_device, command_pool, 1, &command_buffer);
}

fn copyBuffer(
    logical_device: c.VkDevice,
    command_pool: c.VkCommandPool,
    graphics_queue: c.VkQueue,
    src_buffer: c.VkBuffer,
    dst_buffer: c.VkBuffer,
    size: c.VkDeviceSize,
) void {
    const command_buffer = beginSingleTimeCommands(logical_device, command_pool);

    const copy_region = c.VkBufferCopy{
        .srcOffset = 0,
        .dstOffset = 0,
        .size = size,
    };
    c.vkCmdCopyBuffer(command_buffer, src_buffer, dst_buffer, 1, &copy_region);

    endSingleTimeCommands(logical_device, command_pool, graphics_queue, command_buffer);
}

fn transitionImageLayout(
    logical_device: c.VkDevice,
    command_pool: c.VkCommandPool,
    graphics_queue: c.VkQueue,
    image: c.VkImage,
    format: c.VkFormat,
    old_layout: c.VkImageLayout,
    new_layout: c.VkImageLayout,
) void {
    const command_buffer = beginSingleTimeCommands(logical_device, command_pool);

    _ = format; // TODO - needed for "special transitions in the depth buffer chapter", kept to keep in-sync with the tutorial

    const barrier = c.VkImageMemoryBarrier{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .oldLayout = old_layout,
        .newLayout = new_layout,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .srcAccessMask = 0,
        .dstAccessMask = 0,
    };

    c.vkCmdPipelineBarrier(
        command_buffer,
        0,
        0,
        0,
        0,
        null,
        0,
        null,
        1,
        &barrier,
    );

    endSingleTimeCommands(logical_device, command_pool, graphics_queue, command_buffer);
}

// TODO - continue from Copying Buffer to Image

const Vertex = extern struct {
    pos: linalg.Vec2(f32),
    color: linalg.Vec3(f32),

    const Self = @This();

    fn new(x: f32, y: f32, r: f32, g: f32, b: f32) Self {
        return Self{
            .pos = linalg.Vec2(f32).new(x, y),
            .color = linalg.Vec3(f32).new(r, g, b),
        };
    }

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

const UniformBufferObject = extern struct {
    model: linalg.Mat4(f32),
    view: linalg.Mat4(f32),
    proj: linalg.Mat4(f32),
};

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
