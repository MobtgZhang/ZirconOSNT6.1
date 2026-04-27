//! Registry Hive Data Block (DB) Cell
//! 
//! DB cells are used to store large values that don't fit inline.

const std = @import("std");
const Self = @This();

/// DB cell signature "db"
pub const SIGNATURE: [2]u8 = .{ 'd', 'b' };

/// DB Cell header structure
pub const Header = extern struct {
    /// "db" signature (2 bytes)
    signature: u16,

    /// Reserved (2 bytes)
    reserved: u16,

    /// Data size (4 bytes)
    size: u32,

    /// Checksum of data (4 bytes)
    checksum: u32,

    /// Fixed part size
    pub const SIZE: usize = 12;
};

/// Simple checksum algorithm used by DB cells
pub fn computeChecksum(data: []const u8) u32 {
    var sum: u32 = 0;
    for (data) |byte| {
        sum = (sum >> 31) | (sum << 1);
        sum +%= byte;
    }
    return sum;
}

/// Parsed DB Cell
pub const DbCell = struct {
    /// Data size
    size: u32,

    /// Data checksum
    checksum: u32,

    /// The actual data
    data: []const u8,

    /// Raw data
    raw_data: []const u8,

    /// Parse a DB cell from raw data
    pub fn parse(data: []const u8) !DbCell {
        if (data.len < Header.SIZE) {
            return error.BufferTooSmall;
        }

        if (std.mem.readInt(u16, data[0..2], .little) != 0x6264) {
            return error.InvalidSignature;
        }

        const size = std.mem.readInt(u32, data[4..8], .little);
        const checksum = std.mem.readInt(u32, data[8..12], .little);

        if (data.len < Header.SIZE + size) {
            return error.BufferTooSmall;
        }

        return DbCell{
            .size = size,
            .checksum = checksum,
            .data = data[Header.SIZE..Header.SIZE + size],
            .raw_data = data,
        };
    }

    /// Get the data
    pub fn getData(self: *const DbCell) []const u8 {
        return self.data;
    }

    /// Get the data checksum
    pub fn getChecksum(self: *const DbCell) u32 {
        return self.checksum;
    }

    /// Validate the checksum
    pub fn validateChecksum(self: *const DbCell) bool {
        return self.checksum == computeChecksum(self.data);
    }

    /// Get the data size
    pub fn getSize(self: *const DbCell) u32 {
        return self.size;
    }
};

/// Serialize a DB cell
pub fn serialize(db: *const DbCell, data: []u8) !void {
    const expected_size = Header.SIZE + db.size;
    if (data.len < expected_size) {
        return error.BufferTooSmall;
    }

    @memset(data[0..data.len], 0);

    std.mem.writeInt(u16, data[0..2], 0x6264, .little);
    std.mem.writeInt(u16, data[2..4], 0, .little);
    std.mem.writeInt(u32, data[4..8], db.size, .little);
    std.mem.writeInt(u32, data[8..12], db.checksum, .little);

    @memcpy(data[Header.SIZE..Header.SIZE + db.size], db.data);
}

/// Create a new DB cell with data
pub fn create(data: []const u8) DbCell {
    return DbCell{
        .size = @as(u32, @intCast(data.len)),
        .checksum = computeChecksum(data),
        .data = data,
        .raw_data = &.{},
    };
}

/// Error types
pub const Error = error{
    BufferTooSmall,
    InvalidSignature,
    InvalidOffset,
    InvalidData,
    ChecksumMismatch,
};
