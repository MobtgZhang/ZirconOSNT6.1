const std = @import("std");

const libc = struct {
    extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
    extern "c" fn fread(ptr: *anyopaque, size: usize, nmemb: usize, stream: *anyopaque) usize;
    extern "c" fn fseek(stream: *anyopaque, offset: i64, whence: c_int) i64;
    extern "c" fn ftell(stream: *anyopaque) i64;
    extern "c" fn fclose(stream: *anyopaque) c_int;
    extern "c" fn malloc(size: usize) *anyopaque;
    extern "c" fn free(ptr: *anyopaque) void;
};

pub fn main() void {
    const path = "./hivex/images/rlenvalue_test_hive";
    var path_buf: [256:0]u8 = undefined;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;

    const file = libc.fopen(&path_buf, @ptrCast("rb")) orelse return;
    defer _ = libc.fclose(file);

    _ = libc.fseek(file, 0, 2);
    const size: usize = @intCast(libc.ftell(file));
    _ = libc.fseek(file, 0, 0);

    const ptr = libc.malloc(size);
    if (@intFromPtr(ptr) == 0) return;
    defer libc.free(ptr);

    _ = libc.fread(ptr, 1, size, file);
    const data = @as([*]u8, @ptrCast(ptr))[0..size];

    const root_raw = std.mem.readInt(i32, @as(*const [4]u8, @ptrCast(data[32..36].ptr)), .little);
    std.debug.print("root_cell_offset = {} (0x{x})\n", .{ root_raw, @as(u32, @bitCast(root_raw)) });

    // Scan for 'nk' records  
    var found: usize = 0;
    var i: usize = 0x1000;
    while (i + 4 < size) : (i += 4) {
        if (data[i] == 'n' and data[i+1] == 'k') {
            const rel: i32 = @intCast(@as(i64, @intCast(i)) - 0x1000);
            std.debug.print("nk at 0x{x}, rel={}, flags=0x{x}\n", .{
                i, rel,
                std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(data[i+2..i+4])), .little)
            });
            found += 1;
            if (found >= 5) break;
        }
    }
    if (found == 0) {
        std.debug.print("No 'nk' found!\n", .{});
        // Print first 128 bytes of hbin
        std.debug.print("First 128 bytes at 0x1000:\n", .{});
        var j: usize = 0;
        while (j < 128) : (j += 1) {
            if (j % 16 == 0) std.debug.print("{x:4}: ", .{0x1000+j});
            std.debug.print("{x:2} ", .{data[0x1000+j]});
            if ((j+1) % 16 == 0) std.debug.print("\n", .{});
        }
    }
}
