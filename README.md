# vulkan-game
Just curious how hard Vulkan is to get up and running compared to OpenGL --- We've got the answer, it's a lot more effort!
Following the [Khronos Vulkan tutorial](https://docs.vulkan.org/tutorial/latest/00_Introduction.html), but using Zig instead of C++ because we're here for a good time.

## TODO
- Reread main.zig and do some tidying
- Maybe update build.zig to do shader compilation within zig build system too
- Continue from [Frames in flight](https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/03_Drawing/03_Frames_in_flight.html)

## NOTES
Reviewed code so far after first triangle drawn to screen.

### Parts:
- Vulkan Instance: There is no global state in Vulkan, but there is application-level state. This application-level state is stored in a `VkInstance` object
- Physical Device: Representations of the hardware installed in the system
- Queue Family: All Vulkan commands are executed via a queue to facilitate efficient parallel execution as resources become available. Different types of command are committed to different queues. Physical devices have one or more "queue families" that they can use to run Vulkan commands. In our triangle example we've used two types of queue so far, the graphics queue to run our shaders, and the present queue to display the resulting image on the screen. Not all physical devices compatible with Vulkan can handle all types of queue, so you need to check if the available physical devices support the queue types your application will use. Not all families on a device will support the same types of queue either, so you need to check this too. You can use different queue families on the same device to handle different queues, but I think this may be bad for performance. When you create a handle for a `VkQueue` you wish to use, you have to use the queue family index to specify which queue family (and therefore which physical device) you actually want to use. 
- Logical Device: Representation of a connection to a physical device. This is the primary interface the application will actually use to communicate with the physical devices. 
- Queue: A queue used to execute Vulkan commands. Associated with a logical device.
- Swapchain: An object used to present rendering results to a surface. An abstraction for an array of images which are associated with a surface. Only one image in the swap chain may be displayed on the surface at a time, although multiple images may be queued for presentation. 
- Render Pass: All draw commands are recorded in a render pass instance. A render pass instance defines a set of image resources (called _attachments_) that it will use during rendering. 
- Graphics Pipeline: A series of shaders and fixed-functions to be executed.
- Semaphore: A synchronisation primitive used to wait for some process to finish and/or signal that some process has completed on the GPU.
- Fence: A synchronisation primitive used to wait for some process to finish and/or signal that some process has completed on the host.
