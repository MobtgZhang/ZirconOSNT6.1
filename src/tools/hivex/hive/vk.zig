//! Registry Hive Value Key (VK) Cell
//! 
//! VK cells represent registry values (key-value pairs).

const std = @import("std");
const Self = @This();

/// VK cell signature "vk"
pub const SIGNATURE: [2]u8 = .{ 'v', 'k' };

/// VK flags
pub const Flags = struct {
    pub const NAME_IS_ASCII: u16 = 0x0001;
    pub const NO_EXPORT: u16 = 0x0002;
    pub const UNKNOWN: u16 = 0x0004;
};

/// VK Cell header structure
pub const Header = extern struct {
    /// "vk" signature (2 bytes)
    signature: u16,

    /// Name length in characters (2 bytes)
    name_length: u16,

    /// Data length (4 bytes)
    data_length: u32,

    /// Data offset or inline data indicator (4 bytes)
    data_offset: u32,

    /// Value type (4 bytes)
    value_type: u32,

    /// Flags (2 bytes)
    flags: u16,

    /// Reserved (2 bytes)
    reserved: u16,

    /// Fixed part size
    pub const SIZE: usize = 20;
};

/// Registry value types
pub const ValueType = enum(u32) {
    /// No value type
    NONE = 0x00000000,
    /// Unicode null-terminated string
    SZ = 0x00000001,
    /// Unicode null-terminated string with environment variable references
    EXPAND_SZ = 0x00000002,
    /// Binary data
    BINARY = 0x00000003,
    /// 32-bit unsigned integer
    DWORD = 0x00000004,
    /// 32-bit unsigned integer (big endian)
    DWORD_BIG_ENDIAN = 0x00000005,
    /// Symbolic link
    LINK = 0x00000006,
    /// Multiple unicode null-terminated strings
    MULTI_SZ = 0x00000007,
    /// Resource list (hardware resource description)
    RESOURCE_LIST = 0x00000008,
    /// Full resource descriptor
    FULL_RESOURCE_DESCRIPTOR = 0x00000009,
    /// Resource requirements list
    RESOURCE_REQUIREMENTS_LIST = 0x0000000A,
    /// 64-bit unsigned integer
    QWORD = 0x0000000B,

    /// Get the string representation of the value type
    pub fn getName(self: ValueType) []const u8 {
        return switch (self) {
            .NONE => "REG_NONE",
            .SZ => "REG_SZ",
            .EXPAND_SZ => "REG_EXPAND_SZ",
            .BINARY => "REG_BINARY",
            .DWORD => "REG_DWORD",
            .DWORD_BIG_ENDIAN => "REG_DWORD_BIG_ENDIAN",
            .LINK => "REG_LINK",
            .MULTI_SZ => "REG_MULTI_SZ",
            .RESOURCE_LIST => "REG_RESOURCE_LIST",
            .FULL_RESOURCE_DESCRIPTOR => "REG_FULL_RESOURCE_DESCRIPTOR",
            .RESOURCE_REQUIREMENTS_LIST => "REG_RESOURCE_REQUIREMENTS_LIST",
            .QWORD => "REG_QWORD",
        };
    }
};

/// Maximum inline data size (4 bytes)
pub const MAX_INLINE_DATA: u32 = 0x80000000;

/// Mask for inline data indicator
pub const INLINE_MASK: u32 = 0x80000000;

/// Parsed VK Cell
pub const VkCell = struct {
    /// Value name length
    name_length: u16,

    /// Data length
    data_length: u32,

    /// Data offset (or inline data if INLINE_MASK is set)
    data_offset: u32,

    /// Value type
    value_type: u32,

    /// Flags
    flags: u16,

    /// Value name
    name: []const u8,

    /// Raw data
    raw_data: []const u8,

    /// Create from header and additional data
    pub fn fromHeader(header: *const Header, name: []const u8, data: []const u8) VkCell {
        return VkCell{
            .name_length = header.name_length,
            .data_length = header.data_length,
            .data_offset = header.data_offset,
            .value_type = header.value_type,
            .flags = header.flags,
            .name = name,
            .raw_data = data,
        };
    }

    /// Parse a VK cell from raw data
    pub fn parse(data: []const u8) !VkCell {
        if (data.len < Header.SIZE) {
            return error.BufferTooSmall;
        }

        if (std.mem.readInt(u16, data[0..2], .little) != 0x6B76) {
            return error.InvalidSignature;
        }

        const name_len = std.mem.readInt(u16, data[2..4], .little);
        const data_len = std.mem.readInt(u32, data[4..8], .little);
        const data_off = std.mem.readInt(u32, data[8..12], .little);
        const val_type = std.mem.readInt(u32, data[12..16], .little);
        const flags = std.mem.readInt(u16, data[16..18], .little);

        const name = if (name_len > 0)
            data[Header.SIZE..Header.SIZE + name_len]
        else
            &[_]u8{};

        return VkCell{
            .name_length = name_len,
            .data_length = data_len,
            .data_offset = data_off,
            .value_type = val_type,
            .flags = flags,
            .name = name,
            .raw_data = data,
        };
    }

    /// Check if data is inline
    pub fn isInline(self: *const VkCell) bool {
        return (self.data_offset & INLINE_MASK) != 0;
    }

    /// Check if name is ASCII
    pub fn isNameAscii(self: *const VkCell) bool {
        return (self.flags & Flags.NAME_IS_ASCII) != 0;
    }

    /// Get the value type
    pub fn getValueType(self: *const VkCell) ValueType {
        return @as(ValueType, @enumFromInt(self.value_type)) catch .NONE;
    }

    /// Get the value type name
    pub fn getValueTypeName(self: *const VkCell) []const u8 {
        return self.getValueType().getName();
    }

    /// Get the name as UTF-16LE
    pub fn getNameUtf16(self: *const VkCell) []const u16 {
        return @as([*:0]const u16, @ptrCast(self.name.ptr))[0..self.name.len/2 :0];
    }

    /// Get the name as UTF-8
    pub fn getNameUtf8(self: *const VkCell, allocator: std.mem.Allocator) ![]u8 {
        if (self.name.len == 0) {
            return try allocator.dupe(u8, "");
        }
        const result = try allocator.alloc(u8, self.name.len / 2);
        for (result, 0..) |*c, i| {
            c.* = self.name[i * 2];
        }
        return result;
    }

    /// Get inline data size
    pub fn getInlineDataSize(self: *const VkCell) u32 {
        return self.data_offset & ~INLINE_MASK;
    }

    /// Read string value (REG_SZ, REG_EXPAND_SZ)
    pub fn readString(self: *const VkCell, hive_data: []const u8, allocator: std.mem.Allocator) ![]u8 {
        const data = try self.getData(hive_data);
        const len = std.mem.indexOfScalar(u8, data, 0) orelse data.len;
        return try allocator.dupe(u8, data[0..len]);
    }

    /// Read multi-string value (REG_MULTI_SZ)
    pub fn readMultiString(self: *const VkCell, hive_data: []const u8, allocator: std.mem.Allocator) ![][:0]const u8 {
        const data = try self.getData(hive_data);
        var strings = std.ArrayList([]const u8).init(allocator);
        defer strings.deinit();

        var i: usize = 0;
        while (i < data.len) {
            const len = std.mem.indexOfScalar(u8, data[i..], 0) orelse data.len - i;
            if (len == 0) break;
            try strings.append(data[i..i+len]);
            i += len + 1;
        }

        return strings.toOwnedSlice();
    }

    /// Read DWORD value
    pub fn readDword(self: *const VkCell, hive_data: []const u8) !u32 {
        const data = try self.getData(hive_data);
        if (data.len < 4) return error.BufferTooSmall;
        return std.mem.readInt(u32, data[0..4], .little);
    }

    /// Read QWORD value
    pub fn readQword(self: *const VkCell, hive_data: []const u8) !u64 {
        const data = try self.getData(hive_data);
        if (data.len < 8) return error.BufferTooSmall;
        return std.mem.readInt(u64, data[0..8], .little);
    }

    /// Read binary data
    pub fn readBinary(self: *const VkCell, hive_data: []const u8, allocator: std.mem.Allocator) ![]u8 {
        const data = try self.getData(hive_data);
        return try allocator.dupe(u8, data);
    }

    /// Get the value data
    pub fn getData(self: *const VkCell, hive_data: []const u8) ![]const u8 {
        if (self.isInline()) {
            const inline_size = self.getInlineDataSize();
            const offset = self.raw_data.len - inline_size;
            return self.raw_data[offset..];
        } else {
            const offset = @as(usize, @intCast(@as(i32, @bitCast(self.data_offset))));
            if (offset >= hive_data.len) return error.InvalidOffset;
            return hive_data[offset..offset + self.data_length];
        }
    }
};

/// Serialize a VK cell
pub fn serialize(vk: *const VkCell, data: []u8, _: []const u8) !void {
    if (data.len < Header.SIZE + vk.name.len) {
        return error.BufferTooSmall;
    }

    @memset(data[0..data.len], 0);

    std.mem.writeInt(u16, data[0..2], 0x6B76, .little);
    std.mem.writeInt(u16, data[2..4], vk.name_length, .little);
    std.mem.writeInt(u32, data[4..8], vk.data_length, .little);
    std.mem.writeInt(u32, data[8..12], vk.data_offset, .little);
    std.mem.writeInt(u32, data[12..16], vk.value_type, .little);
    std.mem.writeInt(u16, data[16..18], vk.flags, .little);

    @memcpy(data[Header.SIZE..Header.SIZE + vk.name.len], vk.name);
}

/// Create a VK cell for a string value
pub fn createStringValue(name: []const u8, value: []const u8, value_type: ValueType) VkCell {
    const name_utf16 = name;
    const value_utf16 = value;

    return VkCell{
        .name_length = @as(u16, @intCast(name_utf16.len)),
        .data_length = @as(u32, @intCast(value_utf16.len + 2)),
        .data_offset = MAX_INLINE_DATA | @as(u32, @intCast(value_utf16.len + 2)),
        .value_type = @as(u32, @intFromEnum(value_type)),
        .flags = 0,
        .name = name_utf16,
        .raw_data = &.{},
    };
}

/// Error types
pub const Error = error{
    BufferTooSmall,
    InvalidSignature,
    InvalidOffset,
    InvalidData,
};
