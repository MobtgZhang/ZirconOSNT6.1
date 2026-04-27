//! Registry Hive Key Node (NK) Cell
//!
//! NK cells represent registry keys (named keys).

const std = @import("std");
const Self = @This();

/// NK cell signature "nk"
pub const SIGNATURE = "nk";

/// NK cell class indicator
pub const CLASS_INDICATOR: u16 = 0x20;

/// NK flags
pub const Flags = struct {
    pub const KEY_NO_DELETE: u16 = 0x0001;
    pub const KEY_SYMLINK: u16 = 0x0002;
    pub const KEY_COMPILED_NAME: u16 = 0x0004;
    pub const KEY_PREDEF_HANDLE: u16 = 0x0008;
    pub const KEY_VIRT_ROOT: u16 = 0x0020;
    pub const KEY_VIRT_TARGET: u16 = 0x0040;
    pub const KEY_VIRT_NO_VOLATILE: u16 = 0x0080;
    pub const KEY_SESSION: u16 = 0x0100;
};

/// Class ID (0x20 indicates class name follows)
pub const CLASS_ID: u8 = 0x20;

/// Class name offset indicator
pub const CLASS_NAME_FOLLOWS: i32 = -1;

/// NK Cell structure (fixed part) - corrected byte offsets
pub const Header = extern struct {
    /// "nk" signature (2 bytes)
    signature: u16,

    /// Flags (2 bytes)
    flags: u16,

    /// Last key written time as FILETIME (8 bytes)
    timestamp: u64,

    /// Access bits (4 bytes)
    access_bits: u32,

    /// Number of subkeys (4 bytes)
    subkey_count_stable: u32,

    /// Number of volatile subkeys (4 bytes)
    subkey_count_volatile: u32,

    /// Subkey index offset for stable keys (4 bytes)
    subkey_index_offset_stable: i32,

    /// Subkey index offset for volatile keys (4 bytes)
    subkey_index_offset_volatile: i32,

    /// Number of values (4 bytes)
    value_count: u32,

    /// Security descriptor offset (4 bytes)
    sk_offset: i32,

    /// Class name offset or CLASS_NAME_FOLLOWS (4 bytes)
    class_name_offset: i32,

    /// Maximum subkey name length (4 bytes)
    max_subkey_name_len: u32,

    /// Maximum value name length (4 bytes)
    max_value_name_len: u32,

    /// Maximum value data length (4 bytes)
    max_value_data_len: u32,

    /// Work variable (4 bytes)
    work_var: u32,

    /// Key name length in characters (2 bytes)
    name_length: u16,

    /// Class name length in characters (2 bytes)
    class_name_length: u16,

    /// Fixed part size
    pub const SIZE: usize = 76;
};

/// Parsed NK Cell
pub const NkCell = struct {
    /// Flags
    flags: u16,

    /// Last modified timestamp
    timestamp: u64,

    /// Stable subkey count
    subkey_count_stable: u32,

    /// Volatile subkey count
    subkey_count_volatile: u32,

    /// Stable subkey list offset
    subkey_index_offset_stable: i32,

    /// Volatile subkey list offset
    subkey_index_offset_volatile: i32,

    /// Number of values
    value_count: u32,

    /// Security descriptor offset
    sk_offset: i32,

    /// Value list offset
    value_list_offset: i32,

    /// Class name offset
    class_name_offset: i32,

    /// Maximum subkey name length
    max_subkey_name_len: u32,

    /// Maximum value name length
    max_value_name_len: u32,

    /// Maximum value data length
    max_value_data_len: u32,

    /// Key name
    name: []const u8,

    /// Class name (optional)
    class_name: ?[]const u8,

    /// Raw data
    raw_data: []const u8,

    /// Parse an NK cell from raw data
    pub fn parse(data: []const u8) !NkCell {
        if (data.len < Header.SIZE) {
            return error.BufferTooSmall;
        }

        // Read signature directly from bytes to avoid alignment issues
        const sig_bytes = data[0..2];
        const sig = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(sig_bytes.ptr)), .little);
        const expected_sig: u16 = @as(u16, 'n') | (@as(u16, 'k') << 8);
        if (sig != expected_sig) {
            return error.InvalidSignature;
        }

        const name_len = std.mem.readInt(u16, data[74..76], .little);
        if (data.len < Header.SIZE + name_len) {
            return error.BufferTooSmall;
        }

        const name = data[Header.SIZE .. Header.SIZE + name_len];

        var class_name: ?[]const u8 = null;
        const class_name_off = std.mem.readInt(i32, data[40..44], .little);
        if (class_name_off == CLASS_NAME_FOLLOWS) {
            const class_len = std.mem.readInt(u16, data[76..78], .little);
            const class_start = Header.SIZE + name_len;
            if (data.len >= class_start + class_len * 2) {
                class_name = data[class_start .. class_start + class_len * 2];
            }
        }

        // Read value list offset at byte 36-40
        const value_list_off = std.mem.readInt(i32, data[36..40], .little);

        return NkCell{
            .flags = std.mem.readInt(u16, data[2..4], .little),
            .timestamp = std.mem.readInt(u64, data[4..12], .little),
            .subkey_count_stable = std.mem.readInt(u32, data[12..16], .little),
            .subkey_count_volatile = std.mem.readInt(u32, data[16..20], .little),
            .subkey_index_offset_stable = std.mem.readInt(i32, data[20..24], .little),
            .subkey_index_offset_volatile = std.mem.readInt(i32, data[24..28], .little),
            .value_count = std.mem.readInt(u32, data[28..32], .little),
            .sk_offset = std.mem.readInt(i32, data[32..36], .little),
            .value_list_offset = value_list_off,
            .class_name_offset = class_name_off,
            .max_subkey_name_len = std.mem.readInt(u32, data[44..48], .little),
            .max_value_name_len = std.mem.readInt(u32, data[48..52], .little),
            .max_value_data_len = std.mem.readInt(u32, data[52..56], .little),
            .name = name,
            .class_name = class_name,
            .raw_data = data,
        };
    }

    /// Get the key name as a UTF-16LE string
    pub fn getName(self: *const NkCell) [:0]const u16 {
        const name_len = @min(self.name.len, 512);
        return @as([*:0]const u16, @alignCast(@ptrCast(self.name.ptr)))[0 .. name_len / 2 :0];
    }

    /// Get the key name as UTF-8
    pub fn getNameUtf8(self: *const NkCell, allocator: std.mem.Allocator) ![]u8 {
        const name_len = self.name.len;
        if (name_len == 0) {
            return try allocator.dupe(u8, "");
        }
        var result = try allocator.alloc(u8, name_len);
        var i: usize = 0;
        while (i < name_len and i < self.name.len - 1) : (i += 2) {
            result[i / 2] = self.name[i];
        }
        return result[0 .. self.name.len / 2];
    }

    /// Check if this is a root key
    pub fn isRootKey(self: *const NkCell) bool {
        return (self.flags & Flags.KEY_VIRT_ROOT) != 0 or self.subkey_count_volatile > 0;
    }

    /// Check if this key is volatile
    pub fn isVolatile(self: *const NkCell) bool {
        return (self.flags & Flags.KEY_VIRT_NO_VOLATILE) != 0;
    }

    /// Check if this key is a symbolic link
    pub fn isSymlink(self: *const NkCell) bool {
        return (self.flags & Flags.KEY_SYMLINK) != 0;
    }

    /// Check if this key can be deleted
    pub fn canDelete(self: *const NkCell) bool {
        return (self.flags & Flags.KEY_NO_DELETE) == 0;
    }

    /// Check if this key has a class name
    pub fn hasClassName(self: *const NkCell) bool {
        return self.class_name != null or self.class_name_offset == CLASS_NAME_FOLLOWS;
    }

    /// Check if this key has stable subkeys
    pub fn hasStableSubkeys(self: *const NkCell) bool {
        return self.subkey_index_offset_stable != 0;
    }

    /// Check if this key has volatile subkeys
    pub fn hasVolatileSubkeys(self: *const NkCell) bool {
        return self.subkey_index_offset_volatile != 0;
    }

    /// Check if this key has values
    pub fn hasValues(self: *const NkCell) bool {
        return self.value_count > 0;
    }

    /// Check if this key has a security descriptor
    pub fn hasSecurityDescriptor(self: *const NkCell) bool {
        return self.sk_offset != 0;
    }

    /// Get total subkey count
    pub fn getSubkeyCount(self: *const NkCell) u32 {
        return self.subkey_count_stable + self.subkey_count_volatile;
    }
};

/// Serialize an NK cell
pub fn serialize(nk: *const NkCell, data: []u8) !void {
    if (data.len < Header.SIZE + nk.name.len) {
        return error.BufferTooSmall;
    }

    @memset(data[0..data.len], 0);

    std.mem.writeInt(u16, data[0..2], 0x6B6E, .little);
    std.mem.writeInt(u16, data[2..4], nk.flags, .little);
    std.mem.writeInt(u64, data[4..12], nk.timestamp, .little);
    std.mem.writeInt(u32, data[12..16], nk.subkey_count_stable, .little);
    std.mem.writeInt(u32, data[16..20], nk.subkey_count_volatile, .little);
    std.mem.writeInt(i32, data[20..24], nk.subkey_index_offset_stable, .little);
    std.mem.writeInt(i32, data[24..28], nk.subkey_index_offset_volatile, .little);
    std.mem.writeInt(u32, data[28..32], nk.value_count, .little);
    std.mem.writeInt(i32, data[32..36], nk.sk_offset, .little);
    std.mem.writeInt(i32, data[40..44], nk.class_name_offset, .little);
    std.mem.writeInt(u32, data[44..48], nk.max_subkey_name_len, .little);
    std.mem.writeInt(u32, data[48..52], nk.max_value_name_len, .little);
    std.mem.writeInt(u32, data[52..56], nk.max_value_data_len, .little);
    std.mem.writeInt(u16, data[74..76], @as(u16, @intCast(nk.name.len)), .little);
    std.mem.writeInt(u16, data[76..78], if (nk.class_name) |cn| @as(u16, @intCast(cn.len / 2)) else 0, .little);

    @memcpy(data[Header.SIZE .. Header.SIZE + nk.name.len], nk.name);

    if (nk.class_name) |cn| {
        @memcpy(data[Header.SIZE + nk.name.len .. Header.SIZE + nk.name.len + cn.len], cn);
    }
}

/// Error types
pub const Error = error{
    BufferTooSmall,
    InvalidSignature,
    InvalidOffset,
    InvalidData,
};
