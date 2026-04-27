//! Registry Hive Cell Management
//! 
//! Cells are the basic allocation unit in hive files.
//! Positive size = allocated, Negative size = free block

const std = @import("std");
const Self = @This();

/// Cell header (4 bytes for size)
pub const CELL_HEADER_SIZE: usize = 4;

/// Minimum cell alignment
pub const CELL_ALIGNMENT: usize = 8;

/// Cell type identifiers
pub const CellTypeTag = enum(u16) {
    nk = 0x6B6E, // "nk"
    vk = 0x6B76, // "vk"
    sk = 0x6B73, // "sk"
    lf = 0x6C66, // "lf"
    lh = 0x6C68, // "lh"
    ri = 0x6972, // "ri"
    db = 0x6264, // "db"
    subkey_list = 0x6C,  // "l" (generic)
};

/// A cell in the hive
pub const Cell = struct {
    size: i32,
    data: []u8,

    /// Check if the cell is allocated
    pub fn isAllocated(self: *const Cell) bool {
        return self.size > 0;
    }

    /// Check if the cell is free
    pub fn isFree(self: *const Cell) bool {
        return self.size < 0;
    }

    /// Get the absolute size of the cell
    pub fn getSize(self: *const Cell) u32 {
        return @as(u32, @intCast(@abs(self.size)));
    }

    /// Get the cell type from the data
    pub fn getType(self: *const Cell) ?CellTypeTag {
        if (self.data.len < 2) {
            return null;
        }
        const tag = std.mem.readInt(u16, self.data[0..2], .little);
        return @as(?CellTypeTag, @enumFromInt(tag)) catch null;
    }

    /// Get offset relative to hive data start
    pub fn getOffset(self: *const Cell, base: usize) usize {
        const ptr = @intFromPtr(self.data.ptr) - base;
        return @as(usize, @intCast(ptr));
    }

    /// Calculate aligned size for a cell
    pub fn alignCellSize(size: u32) u32 {
        return (size + @as(u32, @intCast(CELL_HEADER_SIZE)) + 7) & ~@as(u32, 7);
    }
};

/// Cell allocator for managing free space
pub const CellAllocator = struct {
    /// Base pointer to hive data
    data: []u8,

    /// Current hbin offset
    hbin_offset: u32,

    /// Total hbin size
    hbin_size: u32,

    /// End of last cell in hbin
    end_of_last_cell: u32,

    /// Total free space
    total_free: u32,

    /// Largest free block
    largest_free: u32,

    /// Free blocks list
    free_blocks: std.ArrayList(FreeBlock),

    /// Allocate a new cell
    pub fn allocate(self: *CellAllocator, size: u32) !i32 {
        const aligned_size = (size + CELL_HEADER_SIZE + 7) & ~@as(u32, 7);

        // Try to find a suitable free block
        for (self.free_blocks.items, 0..) |block, i| {
            if (block.size >= aligned_size) {
                const offset = block.offset;
                self.free_blocks.items[i] = self.free_blocks.pop();
                self.total_free -%= aligned_size;
                return @as(i32, @intCast(offset));
            }
        }

        // Allocate at end of hbin
        if (self.end_of_last_cell + aligned_size > self.hbin_size) {
            return error.OutOfMemory;
        }

        const offset = self.end_of_last_cell;
        self.end_of_last_cell +%= aligned_size;
        self.total_free -%= aligned_size;

        return @as(i32, @intCast(offset));
    }

    /// Free a cell
    pub fn free(self: *CellAllocator, offset: i32, size: u32) !void {
        const aligned_size = (size + 7) & ~@as(u32, 7);
        try self.free_blocks.append(.{ .offset = @as(u32, @intCast(offset)), .size = aligned_size });
        self.total_free +%= aligned_size;
        if (aligned_size > self.largest_free) {
            self.largest_free = aligned_size;
        }
    }

    /// Reallocate a cell
    pub fn reallocate(self: *CellAllocator, offset: i32, old_size: u32, new_size: u32) !i32 {
        try self.free(self, offset, old_size);
        return self.allocate(new_size);
    }

    /// Find a free block of at least the given size
    pub fn findFreeBlock(self: *const CellAllocator, size: u32) ?FreeBlock {
        for (self.free_blocks.items) |block| {
            if (block.size >= size) {
                return block;
            }
        }
        return null;
    }

    /// Coalesce adjacent free blocks
    pub fn coalesce(self: *CellAllocator) void {
        if (self.free_blocks.items.len < 2) return;

        std.mem.sort(FreeBlock, self.free_blocks.items, {}, struct {
            fn less(_: void, a: FreeBlock, b: FreeBlock) bool {
                return a.offset < b.offset;
            }
        }.less);

        var i: usize = 0;
        while (i < self.free_blocks.items.len - 1) : (i += 1) {
            const curr = &self.free_blocks.items[i];
            const next = &self.free_blocks.items[i + 1];
            if (curr.offset + curr.size == next.offset) {
                curr.size +%= next.size;
                _ = self.free_blocks.orderedRemove(i + 1);
                if (i > 0) i -= 1;
            }
        }
    }
};

/// Information about a free block
pub const FreeBlock = struct {
    offset: u32,
    size: u32,
};

/// Parse a cell from hive data
pub fn parseCell(data: []const u8, offset: i32) !Cell {
    if (offset < 0 or @as(usize, @intCast(offset)) >= data.len) {
        return error.InvalidOffset;
    }

    const size_off = @as(usize, @intCast(offset));
    if (size_off + 4 > data.len) {
        return error.BufferTooSmall;
    }

    const size = @as(i32, @bitCast(std.mem.readInt(u32, data[size_off..size_off+4], .little)));
    const abs_size = @as(u32, @intCast(@abs(size)));

    if (size_off + 4 + abs_size > data.len) {
        return error.CellOverflow;
    }

    return Cell{
        .size = size,
        .data = data[size_off + 4..size_off + 4 + abs_size],
    };
}

/// Write a cell header
pub fn writeCellHeader(data: []u8, offset: i32, size: i32) !void {
    const off = @as(usize, @intCast(offset));
    if (off + 4 > data.len) {
        return error.BufferTooSmall;
    }
    std.mem.writeInt(u32, data[off..off+4], @as(u32, @bitCast(size)), .little);
}

/// Calculate aligned size for a cell
pub fn alignCellSize(size: u32) u32 {
    return (size + CELL_HEADER_SIZE + 7) & ~@as(u32, 7);
}

/// Error types
pub const Error = error{
    BufferTooSmall,
    InvalidOffset,
    CellOverflow,
    OutOfMemory,
    InvalidSize,
};
