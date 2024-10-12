# vulkan-game
Just curious how hard Vulkan is to get up and running compared to OpenGL --- We've got the answer, it's a lot more effort!
Following the [Khronos Vulkan tutorial](https://docs.vulkan.org/tutorial/latest/00_Introduction.html), but using Zig instead of C++ because we're here for a good time.

## TODO
- Reread main.zig and do some tidying
- Maybe update build.zig to do shader compilation within zig build system too
- Continue from [Frames in flight](https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/03_Drawing/03_Frames_in_flight.html)

## NOTES
Reviewed code so far after first triangle drawn to screen.

first a diagram test, might be useful!
```mermaid
graph TD;
    A-->B
    A-->C
    B-->D
    C-->D
```

```mermaid
sequenceDiagram
    participant Alice
    participant Bob
    Alice->>John: Hello John, how are you?
    loop HealthCheck
        John->>John: Fight against hypochondria
    end
    Note right of John: Rational thoughts <br/>prevail!
    John-->>Alice: Great!
    John->>Bob: How about you?
    Bob-->>John: Jolly good!
```

```mermaid
gantt
dateFormat  YYYY-MM-DD
title Adding GANTT diagram to mermaid
excludes weekdays 2014-01-10

section A section
Completed task            :done,    des1, 2014-01-06,2014-01-08
Active task               :active,  des2, 2014-01-09, 3d
Future task               :         des3, after des2, 5d
Future task2               :         des4, after des3, 5d

```
