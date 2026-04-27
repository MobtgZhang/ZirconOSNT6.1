//! Windows Registry Hive File Header
//!
//! The hive header is 4096 bytes and contains metadata about the hive file.

const std = @import("std");
const Endian = std.builtin.Endian;
const Self = @This();

/// Type alias for the header struct
pub const HiveHeader = Self;

/// Hive header signature "regf"
pub const SIGNATURE = "regf";

/// Header size in bytes
pub const HEADER_SIZE: usize = 4096;

/// Signature field (4 bytes)
signature: [4]u8,

/// Sequence number (4 bytes)
sequence_number: u32,

/// Last modified timestamp as FILETIME (8 bytes)
timestamp: u64,

/// Major version number (4 bytes)
major_version: u32,

/// Minor version number (4 bytes)
minor_version: u32,

/// File type (4 bytes)
/// 0 = normal, 1 = external
file_type: u32,

/// File format (4 bytes)
/// 0 = direct memory load, 1 = logical hive
file_format: u32,

/// Offset to root cell relative to header (4 bytes)
root_cell_offset: i32,

/// Size of hbin blocks (4 bytes)
hbin_size: u32,

/// Cluster factor (4 bytes)
cluster_factor_index: u32,

/// File size in bytes (4 bytes)
file_size: u32,

/// Offset to first hbin block (4 bytes)
hbin_offset: u32,

/// Size of first hbin block (4 bytes)
hbin_size2: u32,

/// Header checksum (4 bytes)
checksum: u32,

/// Reserved area 1 (65 bytes)
reserved1: [65]u8,

/// Boot type (4 bytes)
boot_type: u32,

/// Boot optional data length (4 bytes)
boot_optional_data_length: u32,

/// Reserved area 2 (372 bytes)
reserved2: [372]u8,

/// Thunk list offset (4 bytes)
thunk_list_offset: u32,

/// Reserved area 3 (8 bytes)
reserved3: [8]u8,

/// Checksum of hbin blocks (4 bytes)
checksum_hbin: u32,

/// Reserved area 4 (428 bytes)
reserved4: [428]u8,

/// Create a new header with default values
pub fn init() Self {
    return .{
        .signature = .{ 'r', 'e', 'g', 'f' },
        .sequence_number = 1,
        .timestamp = 0,
        .major_version = 1,
        .minor_version = 3,
        .file_type = 0,
        .file_format = 1,
        .root_cell_offset = 0,
        .hbin_size = 4096,
        .cluster_factor_index = 1,
        .file_size = 0,
        .hbin_offset = 4096,
        .hbin_size2 = 4096,
        .checksum = 0,
        .reserved1 = .{0} ** 65,
        .boot_type = 0,
        .boot_optional_data_length = 0,
        .reserved2 = .{0} ** 372,
        .thunk_list_offset = 0,
        .reserved3 = .{0} ** 8,
        .checksum_hbin = 0,
        .reserved4 = .{0} ** 428,
    };
}

    /// Parse header from binary data
pub fn parse(data: []const u8) !Self {
    if (data.len < HEADER_SIZE) {
        return error.BufferTooSmall;
    }

    return Self{
        .signature = data[0..4].*,
        .sequence_number = std.mem.readInt(u32, data[4..8], .little),
        .timestamp = std.mem.readInt(u64, data[8..16], .little),
        .major_version = std.mem.readInt(u32, data[16..20], .little),
        .minor_version = std.mem.readInt(u32, data[20..24], .little),
        .file_type = std.mem.readInt(u32, data[24..28], .little),
        .file_format = std.mem.readInt(u32, data[28..32], .little),
        .root_cell_offset = std.mem.readInt(i32, data[32..36], .little),
        .hbin_size = std.mem.readInt(u32, data[36..40], .little),
        .cluster_factor_index = std.mem.readInt(u32, data[40..44], .little),
        .file_size = std.mem.readInt(u32, data[44..48], .little),
        .hbin_offset = std.mem.readInt(u32, data[48..52], .little),
        .hbin_size2 = std.mem.readInt(u32, data[52..56], .little),
        .checksum = std.mem.readInt(u32, data[56..60], .little),
        .reserved1 = data[60..125].*,
        .boot_type = std.mem.readInt(u32, data[125..129], .little),
        .boot_optional_data_length = std.mem.readInt(u32, data[129..133], .little),
        .reserved2 = data[133..505].*,
        .thunk_list_offset = std.mem.readInt(u32, data[505..509], .little),
        .reserved3 = data[509..517].*,
        .checksum_hbin = std.mem.readInt(u32, data[517..521], .little),
        .reserved4 = data[521..949].*,
    };
}

/// Serialize header to binary data
pub fn serialize(self: *const Self, data: []u8) !void {
    if (data.len < HEADER_SIZE) {
        return error.BufferTooSmall;
    }

    std.mem.copyForwards(u8, data[0..4], &self.signature);
    std.mem.writeInt(u32, data[4..8], self.sequence_number, .little);
    std.mem.writeInt(u64, data[8..16], self.timestamp, .little);
    std.mem.writeInt(u32, data[16..20], self.major_version, .little);
    std.mem.writeInt(u32, data[20..24], self.minor_version, .little);
    std.mem.writeInt(u32, data[24..28], self.file_type, .little);
    std.mem.writeInt(u32, data[28..32], self.file_format, .little);
    std.mem.writeInt(i32, data[32..36], self.root_cell_offset, .little);
    std.mem.writeInt(u32, data[36..40], self.hbin_size, .little);
    std.mem.writeInt(u32, data[40..44], self.cluster_factor_index, .little);
    std.mem.writeInt(u32, data[44..48], self.file_size, .little);
    std.mem.writeInt(u32, data[48..52], self.hbin_offset, .little);
    std.mem.writeInt(u32, data[52..56], self.hbin_size2, .little);
    std.mem.writeInt(u32, data[56..60], self.checksum, .little);
    std.mem.copyForwards(u8, data[60..125], &self.reserved1);
    std.mem.writeInt(u32, data[125..129], self.boot_type, .little);
    std.mem.writeInt(u32, data[129..133], self.boot_optional_data_length, .little);
    std.mem.copyForwards(u8, data[133..505], &self.reserved2);
    std.mem.writeInt(u32, data[505..509], self.thunk_list_offset, .little);
    std.mem.copyForwards(u8, data[509..517], &self.reserved3);
    std.mem.writeInt(u32, data[517..521], self.checksum_hbin, .little);
    std.mem.copyForwards(u8, data[521..949], &self.reserved4);
}

/// Validate header signature and version
pub fn validate(self: *const Self) bool {
    const sig_valid = std.mem.eql(u8, &self.signature, SIGNATURE);
    // BCD files may have non-standard version numbers, so we check signature only
    // and allow any major version (1, 3, or potentially others like 4 for BCD)
    if (!sig_valid) {
        return false;
    }
    return true;
}

/// Check if the header is a valid logical hive format
pub fn isLogicalHive(self: *const Self) bool {
    return self.file_format == 1;
}

/// Check if the header is a direct memory load format
pub fn isDirectLoad(self: *const Self) bool {
    return self.file_format == 0;
}

/// Compute checksum of the header (excluding checksum field)
pub fn computeChecksum(self: *const Self, data: []const u8) u32 {
    _ = self;
    var sum: u32 = 0;
    const checksum_offset = 56;
    const checksum_end = 60;

    var i: usize = 0;
    while (i < checksum_offset) : (i += 4) {
        sum +%= std.mem.readInt(u32, data[i..][0..4], .little);
    }

    i = checksum_end;
    while (i < HEADER_SIZE) : (i += 4) {
        sum +%= std.mem.readInt(u32, data[i..][0..4], .little);
    }

    return sum;
}

/// Validate header checksum
pub fn validateChecksum(self: *const Self, data: []const u8) bool {
    return self.checksum == self.computeChecksum(data);
}

/// Get the timestamp as a formatted string
pub fn getTimestampString(self: *const Self) [64]u8 {
    var buf: [64]u8 = undefined;
    const timestamp = self.timestamp;
    if (timestamp == 0) {
        @memcpy(buf[0..3], "N/A");
        return buf;
    }
    const seconds = @divTrunc(timestamp, 10_000_000);
    const days = @divTrunc(seconds, 86400);
    const year: u32 = @intCast(1601 + @divTrunc(days, 365));
    _ = std.fmt.bufPrintZ(&buf, "{d:04}-??-?? ??:??:??", .{year}) catch "";
    return buf;
}

/// File type constants
pub const FileType = enum(u32) {
    normal = 0,
    external = 1,
};

/// File format constants
pub const FileFormat = enum(u32) {
    direct_memory_load = 0,
    logical_hive = 1,
};

/// Error types
pub const Error = error{
    BufferTooSmall,
    InvalidSignature,
    InvalidVersion,
    InvalidChecksum,
    InvalidOffset,
};
