const std = @import("std");
const sshfling = @import("sshfling.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const arguments = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, arguments);
    std.process.exit(try sshfling.run(allocator, arguments[1..]));
}
