const std = @import("std");
const fatal = @import("./fatal.zig").fatal;

// NOTE - using `extern struct` to guarantee C ABI struct memory layout, think we require this with column major matrices for passing data to the GPU
//        I think this won't actually change anything? Since all the fields are integer fields with the same type? So there's no alignment trickery to worry about

pub fn degreesToRadians(deg: f32) f32 {
    return std.math.pi * deg / 180;
}

pub fn radiansToDegrees(rad: f32) f32 {
    return 180 * rad / std.math.pi;
}

pub fn Vec2(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,

        const Self = @This();

        pub fn new(x: T, y: T) Self {
            return .{ .x = x, .y = y };
        }
    };
}

pub fn Vec3(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,
        z: T,

        const Self = @This();

        pub fn new(x: T, y: T, z: T) Self {
            return .{ .x = x, .y = y, .z = z };
        }

        pub fn isNormalised(self: Self) bool {
            return std.math.pow(T, self.x, 2) + std.math.pow(T, self.y, 2) + std.math.pow(T, self.z, 2) == 1;
        }
    };
}

pub fn Vec4(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,
        z: T,
        w: T,

        const Self = @This();

        pub fn new(x: T, y: T, z: T, w: T) Self {
            return .{ .x = x, .y = y, .z = z, .w = w };
        }
    };
}

pub fn Mat2(comptime T: type) type {
    return extern struct {
        col1: Vec2(T),
        col2: Vec2(T),

        const Self = @This();

        pub fn new(col1: Vec2(T), col2: Vec2(T)) Self {
            return .{ .col1 = col1, .col2 = col2 };
        }
    };
}

pub fn Mat3(comptime T: type) type {
    return extern struct {
        col1: Vec3(T),
        col2: Vec3(T),
        col3: Vec3(T),

        const Self = @This();

        pub fn new(col1: Vec3(T), col2: Vec3(T), col3: Vec3(T)) Self {
            return .{ .col1 = col1, .col2 = col2, .col3 = col3 };
        }
    };
}

pub fn Mat4(comptime T: type) type {
    return extern struct {
        col1: Vec4(T),
        col2: Vec4(T),
        col3: Vec4(T),
        col4: Vec4(T),

        const Self = @This();

        pub fn new(col1: Vec4(T), col2: Vec4(T), col3: Vec4(T), col4: Vec4(T)) Self {
            return .{ .col1 = col1, .col2 = col2, .col3 = col3, .col4 = col4 };
        }

        pub fn translation(trans: Vec3(T)) Self {
            return .{
                .col1 = .{ 1, 0, 0, 0 },
                .col2 = .{ 0, 1, 0, 0 },
                .col3 = .{ 0, 0, 1, 0 },
                .col4 = .{ trans.x, trans.y, trans.z, 1 },
            };
        }

        // rotation by angle about normalised vector
        pub fn rotation(angle: f32, axis: Vec3(T)) Self {
            if (!axis.isNormalised()) {
                fatal("axis must be normalised");
            }
            const s = @sin(angle);
            const c = @cos(angle);
            return .{
                .col1 = .{
                    .x = axis.x * axis.x * (1 - c) + c,
                    .y = axis.x * axis.y * (1 - c) + axis.z * s,
                    .z = axis.x * axis.z * (1 - c) - axis.y * s,
                    .w = 0,
                },
                .col2 = .{
                    .x = axis.x * axis.y * (1 - c) - axis.z * s,
                    .y = axis.y * axis.y * (1 - c) + c,
                    .z = axis.y * axis.z * (1 - c) + axis.x * s,
                    .w = 0,
                },
                .col3 = .{
                    .x = axis.x * axis.z * (1 - c) + axis.y * s,
                    .y = axis.y * axis.z * (1 - c) - axis.x * s,
                    .z = axis.z * axis.z * (1 - c) + c,
                    .w = 0,
                },
                .col4 = .{
                    .x = 0,
                    .y = 0,
                    .z = 0,
                    .w = 1,
                },
            };
        }

        // a rotation followed by a translation
        pub fn rigidBodyTransform(angle: f32, axis: Vec3(T), trans: Vec3(T)) Self {
            if (!axis.isNormalised()) {
                fatal("axis must be normalised");
            }
            const s = @sin(angle);
            const c = @cos(angle);
            return .{
                .col1 = .{
                    .x = axis.x * axis.x * (1 - c) + c,
                    .y = axis.x * axis.y * (1 - c) + axis.z * s,
                    .z = axis.x * axis.z * (1 - c) - axis.y * s,
                    .w = 0,
                },
                .col2 = .{
                    .x = axis.x * axis.y * (1 - c) - axis.z * s,
                    .y = axis.y * axis.y * (1 - c) + c,
                    .z = axis.y * axis.z * (1 - c) + axis.x * s,
                    .w = 0,
                },
                .col3 = .{
                    .x = axis.x * axis.z * (1 - c) + axis.y * s,
                    .y = axis.y * axis.z * (1 - c) - axis.x * s,
                    .z = axis.z * axis.z * (1 - c) + c,
                    .w = 0,
                },
                .col4 = .{
                    .x = trans.x,
                    .y = trans.y,
                    .z = trans.z,
                    .w = 1,
                },
            };
        }
    };
}
