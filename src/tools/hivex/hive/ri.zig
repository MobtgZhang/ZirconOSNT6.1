//! Registry Hive Root Index (RI) Cell
//! 
//! RI cells are used when there are too many subkeys to fit in a single LF/LH cell.
//! They contain offsets to other index cells (LF, LH, or nested RI).

const std = @import("std");
const Self = @This();

/// RI cell signature "ri"
pub const SIGNATURE: [2]u8 = .{ 'r', 'i' };

/// RI Cell header structure
pub const Header = extern struct {
    /// "ri" signature (2 bytes)
    signature: u16,

    /// Reserved (2 bytes)
    reserved: u16,

    /// Number of offsets (2 bytes)
    count: u16,

    /// Fixed part size
    pub const SIZE: usize = 4;
};

/// Offsets entry (variable size, 4 bytes each)
pub const OffsetsEntry = struct {
    /// Offset to index cell (4 bytes)
    offset: i32,
};

/// Parsed RI Cell
pub const RiCell = struct {
    /// Number of offsets
    count: u16,

    /// Raw data
    raw_data: []const u8,

    /// Parse an RI cell from raw data
    pub fn parse(data: []const u8) !RiCell {
        if (data.len < Header.SIZE) {
            return error.BufferTooSmall;
        }

        if (std.mem.readInt(u16, data[0..2], .little) != 0x6972) {
            return error.InvalidSignature;
        }

        const count = std.mem.readInt(u16, data[2..4], .little);
        const expected_size = Header.SIZE + count * @sizeOf(i32);

        if (data.len < expected_size) {
            return error.BufferTooSmall;
        }

        return RiCell{
            .count = count,
            .raw_data = data,
        };
    }

    /// Get the number of offset entries
    pub fn getCount(self: *const RiCell) u16 {
        return self.count;
    }

    /// Get offset at index
    pub fn getOffset(self: *const RiCell, index: usize) ?i32 {
        if (index >= self.count) return null;
        const off = Header.SIZE + index * @sizeOf(i32);
        const offset_bytes = self.raw_data[off..off+4];
        return std.mem.readInt(i32, @as(*const [4]u8, @ptrCast(offset_bytes.ptr)), .little);
    }

    /// Iterate over all offsets
    pub fn iterate(self: *const RiCell) RiIterator {
        return RiIterator{
            .ri = self,
            .current_index = 0,
        };
    }
};

/// Iterator for RI cell offsets
pub const RiIterator = struct {
    ri: *const RiCell,
    current_index: usize,

    /// Get the next offset
    pub fn next(self: *RiIterator) ?i32 {
        if (self.current_index >= self.ri.count) return null;
        const offset = self.ri.getOffset(self.current_index);
        self.current_index += 1;
        return offset;
    }

    /// Check if there are more offsets
    pub fn hasNext(self: *const RiIterator) bool {
        return self.current_index < self.ri.count;
    }

    /// Reset the iterator
    pub fn reset(self: *RiIterator) void {
        self.current_index = 0;
    }
};

/// Serialize an RI cell
pub fn serialize(ri: *const RiCell, data: []u8) !void {
    const expected_size = Header.SIZE + ri.count * @sizeOf(i32);
    if (data.len < expected_size) {
        return error.BufferTooSmall;
    }

    @memset(data[0..data.len], 0);

    std.mem.writeInt(u16, data[0..2], 0x6972, .little);
    std.mem.writeInt(u16, data[2..4], ri.count, .little);

    for (0..ri.count) |i| {
        const off = Header.SIZE + i * @sizeOf(i32);
        if (ri.getOffset(i)) |offset| {
            std.mem.writeInt(i32, data[off..off+4], offset, .little);
        }
    }
}

/// Create a new RI cell
pub fn create(count: u16) RiCell {
    return RiCell{
        .count = count,
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
