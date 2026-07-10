const std = @import("std");
const c = @cImport({
    @cInclude("sshfling_launcher.h");
});

pub const version = "0.0.0";

pub fn runtimeVersion() []const u8 {
    return std.mem.span(c.sshfling_launcher_version());
}

pub fn run(allocator: std.mem.Allocator, arguments: []const []const u8) !u8 {
    const strings = try allocator.alloc([:0]u8, arguments.len);
    defer allocator.free(strings);
    const pointers = try allocator.alloc([*:0]const u8, arguments.len);
    defer allocator.free(pointers);

    var initialized: usize = 0;
    defer for (strings[0..initialized]) |argument| allocator.free(argument);
    for (arguments, 0..) |argument, index| {
        strings[index] = try allocator.dupeZ(u8, argument);
        initialized += 1;
        pointers[index] = strings[index].ptr;
    }

    const base = if (pointers.len == 0) null else @as([*c]const [*c]const u8, @ptrCast(pointers.ptr));
    return @intCast(c.sshfling_launcher_run(arguments.len, base));
}
