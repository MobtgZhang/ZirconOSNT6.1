//! Registry Hive Binary Block (hbin)
//!
//! hbin blocks are 4KB aligned memory blocks that contain cells.

const std = @import("std");

/// hbin block signature
pub const SIGNATURE = "hbin";

/// Registry Hive Binary Block
pub const HbinBlock = struct {
    /// Offset to next hbin block (relative to this hbin start)
    offset_to_next_hbin: u32,

    /// Size of this hbin block
    size: u32,

    /// First cell offset (relative to this hbin start)
    first_cell_offset: u32,

    /// Size of largest free block
    largest_free_block: u32,

    /// Total free space
    total_free_space: u32,

    /// End of last cell
    end_of_last_cell: u32,

    /// Reserved
    reserved: [12]u8,

    /// Create a new hbin block header
    pub fn init(size: u32) HbinBlock {
        return .{
            .offset_to_next_hbin = size,
            .size = size,
            .first_cell_offset = 0x20,
            .largest_free_block = size - 0x20,
            .total_free_space = size - 0x20,
            .end_of_last_cell = 0x20,
            .reserved = .{0} ** 12,
        };
    }

    /// Parse hbin header from binary data
    pub fn parse(data: []const u8) !HbinBlock {
        if (data.len < 0x20) {
            return error.BufferTooSmall;
        }

        return HbinBlock{
            .offset_to_next_hbin = std.mem.readInt(u32, data[0..4], .little),
            .size = std.mem.readInt(u32, data[4..8], .little),
            .first_cell_offset = std.mem.readInt(u32, data[8..12], .little),
            .largest_free_block = std.mem.readInt(u32, data[12..16], .little),
            .total_free_space = std.mem.readInt(u32, data[16..20], .little),
            .end_of_last_cell = std.mem.readInt(u32, data[20..24], .little),
            .reserved = data[24..36].*,
        };
    }

    /// Serialize hbin header to binary
    pub fn serialize(self: *const HbinBlock, data: []u8) !void {
        if (data.len < 0x20) {
            return error.BufferTooSmall;
        }

        std.mem.writeInt(u32, data[0..4], self.offset_to_next_hbin, .little);
        std.mem.writeInt(u32, data[4..8], self.size, .little);
        std.mem.writeInt(u32, data[8..12], self.first_cell_offset, .little);
        std.mem.writeInt(u32, data[12..16], self.largest_free_block, .little);
        std.mem.writeInt(u32, data[16..20], self.total_free_space, .little);
        std.mem.writeInt(u32, data[20..24], self.end_of_last_cell, .little);
        @memcpy(data[24..36], &self.reserved);
    }

    /// Get the actual data offset (after header)
    pub fn getDataOffset(self: *const HbinBlock) usize {
        _ = self;
        return 0x20;
    }

    /// Get the cell area size
    pub fn getCellAreaSize(self: *const HbinBlock) u32 {
        return self.size - 0x20;
    }

    /// Check if the hbin block is valid
    pub fn validate(self: *const HbinBlock) bool {
        return self.size > 0 and self.first_cell_offset >= 0x20;
    }

    /// Calculate free space after accounting for a cell
    pub fn calculateFreeSpaceAfter(self: *const HbinBlock, cell_size: u32) u32 {
        return self.total_free_space + cell_size;
    }

    /// Update free space info after allocation
    pub fn updateAfterAllocation(self: *HbinBlock, allocated_size: u32) void {
        self.total_free_space -= allocated_size;
        self.end_of_last_cell +%= allocated_size;
        if (self.largest_free_block < self.total_free_space) {
            self.largest_free_block = self.total_free_space;
        }
    }

    /// Update free space info after freeing
    pub fn updateAfterFree(self: *HbinBlock, freed_size: u32) void {
        self.total_free_space +%= freed_size;
        if (self.largest_free_block < freed_size) {
            self.largest_free_block = freed_size;
        }
    }

    /// Iterator for walking through cells in an hbin block
    pub const CellIterator = struct {
        data: []const u8,
        current_offset: usize,
        hbin_start: usize,

        /// Create a new cell iterator
        pub fn init(data: []const u8, hbin_start: usize) CellIterator {
            return .{
                .data = data,
                .current_offset = 0x20,
                .hbin_start = hbin_start,
            };
        }

        /// Get the current cell offset (relative to hbin start)
        pub fn getOffset(self: *const CellIterator) usize {
            return self.current_offset;
        }

        /// Check if there are more cells
        pub fn next(self: *CellIterator) ?CellInfo {
            if (self.current_offset >= self.data.len - 4) {
                return null;
            }

            const cell_size = @as(i32, @bitCast(std.mem.readInt(u32, self.data[self.current_offset..][0..4], .little)));
            if (cell_size == 0) {
                return null;
            }

            const info: CellInfo = .{
                .offset = @as(i32, @intCast(self.current_offset)),
                .size = cell_size,
                .data = self.data[self.current_offset + 4 .. self.current_offset + @as(usize, @intCast(@abs(cell_size)))],
            };

            if (cell_size > 0) {
                self.current_offset += @as(usize, @intCast(cell_size));
            } else {
                self.current_offset += @as(usize, @intCast(@abs(cell_size)));
            }

            // Align to 8 bytes
            self.current_offset = (self.current_offset + 7) & ~@as(usize, 7);

            return info;
        }
    };

    /// Information about a cell
    pub const CellInfo = struct {
        offset: i32,
        size: i32,
        data: []const u8,

        /// Check if this cell is allocated
        pub fn isAllocated(self: *const CellInfo) bool {
            return self.size > 0;
        }

        /// Check if this cell is free
        pub fn isFree(self: *const CellInfo) bool {
            return self.size < 0;
        }

        /// Get the actual size
        pub fn getSize(self: *const CellInfo) u32 {
            return @as(u32, @intCast(@abs(self.size)));
        }
    };
};

/// Error types
pub const Error = error{
    BufferTooSmall,
    InvalidSize,
    InvalidOffset,
    CellOverflow,
};
