//! Registry Value Operations
//! 
//! High-level registry value manipulation.

const std = @import("std");
const vk = @import("../hive/vk.zig");

/// Registry value type
pub const ValueType = vk.ValueType;

/// Registry value
pub const Value = struct {
    /// Value name
    name: []u8,

    /// Value type
    value_type: ValueType,

    /// Value data
    data: []u8,
};

/// Parse a value from VK cell data
pub fn parseFromVkCell(vk_cell: *const vk.VkCell, hive_data: []const u8, allocator: std.mem.Allocator) !Value {
    const name = try vk_cell.getNameUtf8(allocator);
    const value_type = vk_cell.getValueType();

    var data: []u8 = &.{};
    switch (value_type) {
        .SZ, .EXPAND_SZ => {
            data = try vk_cell.readString(hive_data, allocator);
        },
        .DWORD => {
            const dword = try vk_cell.readDword(hive_data);
            data = try allocator.alloc(u8, 4);
            std.mem.writeInt(u32, data, dword, .little);
        },
        .QWORD => {
            const qword = try vk_cell.readQword(hive_data);
            data = try allocator.alloc(u8, 8);
            std.mem.writeInt(u64, data, qword, .little);
        },
        .BINARY => {
            data = try vk_cell.readBinary(hive_data, allocator);
        },
        .MULTI_SZ => {
            const strings = try vk_cell.readMultiString(hive_data, allocator);
            var total_len: usize = 0;
            for (strings) |s| {
                total_len += s.len + 1;
            }
            total_len += 1;
            data = try allocator.alloc(u8, total_len);
            var offset: usize = 0;
            for (strings) |s| {
                @memcpy(data[offset..offset + s.len], s);
                offset += s.len;
                data[offset] = 0;
                offset += 1;
            }
            data[offset] = 0;
        },
        else => {
            data = try vk_cell.readBinary(hive_data, allocator);
        },
    }

    return Value{
        .name = name,
        .value_type = value_type,
        .data = data,
    };
}

/// Read string value
pub fn readString(value: *const Value) ![]u8 {
    if (value.value_type != .SZ and value.value_type != .EXPAND_SZ) {
        return error.InvalidType;
    }
    const len = std.mem.indexOfScalar(u8, value.data, 0) orelse value.data.len;
    return value.data[0..len];
}

/// Read multi-string value
pub fn readMultiString(value: *const Value, allocator: std.mem.Allocator) ![][:0]const u8 {
    if (value.value_type != .MULTI_SZ) {
        return error.InvalidType;
    }

    var strings = std.ArrayList([]const u8).init(allocator);
    defer strings.deinit();

    var i: usize = 0;
    while (i < value.data.len) {
        const len = std.mem.indexOfScalar(u8, value.data[i..], 0) orelse value.data.len - i;
        if (len == 0) break;
        try strings.append(value.data[i..i+len]);
        i += len + 1;
    }

    return strings.toOwnedSlice();
}

/// Read DWORD value
pub fn readDword(value: *const Value) !u32 {
    if (value.value_type != .DWORD) {
        return error.InvalidType;
    }
    if (value.data.len < 4) {
        return error.BufferTooSmall;
    }
    return std.mem.readInt(u32, value.data[0..4], .little);
}

/// Read QWORD value
pub fn readQword(value: *const Value) !u64 {
    if (value.value_type != .QWORD) {
        return error.InvalidType;
    }
    if (value.data.len < 8) {
        return error.BufferTooSmall;
    }
    return std.mem.readInt(u64, value.data[0..8], .little);
}

/// Read binary value
pub fn readBinary(value: *const Value) []u8 {
    return value.data;
}

/// Format value for display
pub fn formatValue(value: *const Value, allocator: std.mem.Allocator) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();

    try writer.print("{s} = ", .{value.name});

    switch (value.value_type) {
        .SZ, .EXPAND_SZ => {
            const str = readString(value) catch "";
            try writer.print("\"{s}\"", .{str});
        },
        .DWORD => {
            const dword = readDword(value) catch 0;
            try writer.print("0x{x:0>8} ({d})", .{ dword, dword });
        },
        .QWORD => {
            const qword = readQword(value) catch 0;
            try writer.print("0x{x:0>16} ({d})", .{ qword, qword });
        },
        .BINARY => {
            if (value.data.len > 0) {
                try writer.print("hex({d}): ", .{value.data.len});
                const max_show = @min(value.data.len, 16);
                for (value.data[0..max_show]) |b| {
                    try writer.print("{x:0>2} ", .{b});
                }
                if (value.data.len > 16) {
                    try writer.print("...", .{});
                }
            }
        },
        .MULTI_SZ => {
            try writer.print("multistring({d}):\n", .{value.data.len});
            const strs = readMultiString(value) catch &.{};
            for (strs) |s| {
                try writer.print("  \"{s}\"\n", .{s});
            }
        },
        else => {
            try writer.print("type 0x{x} ({d} bytes)", .{ @as(u32, @intFromEnum(value.value_type)), value.data.len });
        },
    }

    return buf.toOwnedSlice();
}

/// Create a string value
pub fn createStringValue(name: []const u8, str: []const u8) Value {
    return Value{
        .name = name,
        .value_type = .SZ,
        .data = str,
    };
}

/// Create an expand string value
pub fn createExpandStringValue(name: []const u8, str: []const u8) Value {
    return Value{
        .name = name,
        .value_type = .EXPAND_SZ,
        .data = str,
    };
}

/// Create a DWORD value
pub fn createDwordValue(name: []const u8, dword: u32) Value {
    var data: [4]u8 = undefined;
    std.mem.writeInt(u32, &data, dword, .little);
    return Value{
        .name = name,
        .value_type = .DWORD,
        .data = &data,
    };
}

/// Create a QWORD value
pub fn createQwordValue(name: []const u8, qword: u64) Value {
    var data: [8]u8 = undefined;
    std.mem.writeInt(u64, &data, qword, .little);
    return Value{
        .name = name,
        .value_type = .QWORD,
        .data = &data,
    };
}

/// Create a binary value
pub fn createBinaryValue(name: []const u8, data: []u8) Value {
    return Value{
        .name = name,
        .value_type = .BINARY,
        .data = data,
    };
}

/// Create a multi-string value
pub fn createMultiStringValue(name: []const u8, strings: []const []const u8) Value {
    _ = strings;
    return Value{
        .name = name,
        .value_type = .MULTI_SZ,
        .data = &.{},
    };
}

/// Error types
pub const Error = error{
    InvalidType,
    BufferTooSmall,
    OutOfMemory,
    InvalidData,
};
