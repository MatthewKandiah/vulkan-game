const std = @import("std");

// NOTE - using `extern struct` to guarantee C ABI struct memory layout, think we require this with column major matrices for passing data to the GPU
//        I think this won't actually change anything? Since all the fields are integer fields with the same type? So there's no alignment trickery to worry about

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
    };
}
