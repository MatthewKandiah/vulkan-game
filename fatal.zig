const std = @import("std");

pub fn fatal(comptime mess: []const u8) noreturn {
    std.debug.print(mess, .{});
    std.process.exit(1);
}

pub fn fatalQuiet() noreturn {
    fatal("");
}

pub fn fatalIfNotSuccess(res: c_int, comptime mess: []const u8) void {
    // VK_SUCCESS == 0
    if (res != 0) {
        std.debug.print("res: {}\n", .{res});
        fatal(mess);
    }
}
