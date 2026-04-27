//! Registry Hive Leaf (LF) and Leaf Hashed (LH) Cells
//! 
//! LF/LH cells are fast index structures for subkey lookup.
//! They contain name hashes and offsets to NK cells.

const std = @import("std");
const Self = @This();

/// LF cell signature "lf"
pub const LF_SIGNATURE: [2]u8 = .{ 'l', 'f' };

/// LH cell signature "lh"
pub const LH_SIGNATURE: [2]u8 = .{ 'l', 'h' };

/// LF/LH Entry structure
pub const Entry = struct {
    /// Name hash (2 bytes for LF, 4 bytes for LH)
    hash: [4]u8,

    /// Offset to NK cell (4 bytes)
    nk_offset: i32,

    /// Entry size (LF = 6, LH = 8)
    pub const SIZE: usize = 8;
    pub const SIZE_LF: usize = 6;
};

/// LF Cell header structure
pub const LfHeader = extern struct {
    /// "lf" or "lh" signature (2 bytes)
    signature: u16,

    /// Number of entries (2 bytes)
    count: u16,

    /// Fixed part size
    pub const SIZE: usize = 4;
};

/// Parsed LF Cell
pub const LfCell = struct {
    /// Number of entries
    count: u16,

    /// Entry size (LF = 6, LH = 8)
    entry_size: usize,

    /// Entries (raw bytes)
    entries: []const u8,

    /// Raw data
    raw_data: []const u8,

    /// Parse an LF cell from raw data
    pub fn parse(data: []const u8) !LfCell {
        if (data.len < LfHeader.SIZE) {
            return error.BufferTooSmall;
        }

        const sig = std.mem.readInt(u16, data[0..2], .little);
        if (sig != 0x6C66 and sig != 0x6C68) {
            return error.InvalidSignature;
        }

        const count = std.mem.readInt(u16, data[2..4], .little);
        const entry_size: usize = if (sig == 0x6C66) Entry.SIZE_LF else Entry.SIZE;
        const expected_size = LfHeader.SIZE + count * entry_size;

        if (data.len < expected_size) {
            return error.BufferTooSmall;
        }

        var entries: [256]Entry = undefined;
        for (0..count) |i| {
            const offset = LfHeader.SIZE + i * entry_size;
            if (sig == 0x6C66) {
                @memcpy(entries[i].hash[0..2], data[offset..offset+2]);
                entries[i].hash[2] = 0;
                entries[i].hash[3] = 0;
                entries[i].nk_offset = std.mem.readInt(i32, @as(*const [4]u8, @ptrCast(data[offset+2..offset+6].ptr)), .little);
            } else {
                @memcpy(entries[i].hash[0..4], data[offset..offset+4]);
                entries[i].nk_offset = std.mem.readInt(i32, @as(*const [4]u8, @ptrCast(data[offset+4..offset+8].ptr)), .little);
            }
        }

        return LfCell{
            .count = count,
            .entry_size = entry_size,
            .entries = data[LfHeader.SIZE..LfHeader.SIZE + count * entry_size],
            .raw_data = data,
        };
    }

    /// Check if this is an LH cell
    pub fn isHashed(self: *const LfCell) bool {
        if (self.raw_data.len < 2) return false;
        return std.mem.readInt(u16, self.raw_data[0..2], .little) == 0x6C68;
    }

    /// Get entry count
    pub fn getEntryCount(self: *const LfCell) u16 {
        return self.count;
    }

    /// Find an entry by name
    pub fn findEntry(self: *const LfCell, name: []const u8) ?i32 {
        const hash = computeHash(name, self.isHashed());
        for (0..self.count) |i| {
            const entry_hash = self.raw_data[LfHeader.SIZE + i * self.entry_size..LfHeader.SIZE + i * self.entry_size + 4];
            if (std.mem.eql(u8, entry_hash, &hash)) {
                const offset = LfHeader.SIZE + i * self.entry_size + 4;
                return std.mem.readInt(i32, self.raw_data[offset..offset+4], .little);
            }
        }
        return null;
    }

    /// Get entry at index
    pub fn getEntry(self: *const LfCell, index: usize) ?Entry {
        if (index >= self.count) return null;
        const entry_offset = LfHeader.SIZE + index * self.entry_size;
        const hash_offset = LfHeader.SIZE + index * self.entry_size;
        if (self.entry_size == 6) {
            // LF cell: 2-byte hash + 4-byte offset
            var hash: [4]u8 = .{ 0, 0, 0, 0 };
            @memcpy(hash[0..2], self.raw_data[hash_offset..hash_offset+2]);
            return Entry{
                .hash = hash,
                .nk_offset = std.mem.readInt(i32, @as(*const [4]u8, @ptrCast(self.raw_data[entry_offset+2..entry_offset+6].ptr)), .little),
            };
        } else {
            // LH cell: 4-byte hash + 4-byte offset
            var hash: [4]u8 = .{ 0, 0, 0, 0 };
            @memcpy(hash[0..4], self.raw_data[hash_offset..hash_offset+4]);
            return Entry{
                .hash = hash,
                .nk_offset = std.mem.readInt(i32, @as(*const [4]u8, @ptrCast(self.raw_data[entry_offset+4..entry_offset+8].ptr)), .little),
            };
        }
    }
};

/// Parsed LH Cell
pub const LhCell = LfCell;

/// Compute name hash for LF cells (simple 2-byte hash)
pub fn computeHashLF(name: []const u8) [2]u8 {
    var hash: [2]u8 = .{ 0, 0 };
    for (name, 0..) |c, i| {
        const upper = if (c >= 'a' and c <= 'z') c - 'a' + 'A' else c;
        hash[0] +%= upper;
        hash[1] +%= @as(u8, @intCast(i)) *% upper;
    }
    return hash;
}

/// Compute name hash for LH cells (improved 4-byte hash)
pub fn computeHashLH(name: []const u8) [4]u8 {
    var hash: [4]u8 = .{ 0, 0, 0, 0 };
    var i: usize = 0;
    while (i < name.len) : (i += 2) {
        const char1 = if (name[i] >= 'a' and name[i] <= 'z') name[i] - 'a' + 'A' else name[i];
        hash[0] +%= char1;
        hash[1] +%= @as(u8, @intCast(i)) *% char1;
        if (i + 1 < name.len) {
            const char2 = if (name[i+1] >= 'a' and name[i+1] <= 'z') name[i+1] - 'a' + 'A' else name[i+1];
            hash[2] +%= char2;
            hash[3] +%= @as(u8, @intCast(i + 1)) *% char2;
        }
    }
    return hash;
}

/// Compute name hash (dispatch based on cell type)
pub fn computeHash(name: []const u8, is_lh: bool) [4]u8 {
    if (is_lh) {
        return computeHashLH(name);
    } else {
        const lf_hash = computeHashLF(name);
        return .{ lf_hash[0], lf_hash[1], 0, 0 };
    }
}

/// Serialize an LF cell
pub fn serializeLf(cell: *const LfCell, data: []u8) !void {
    if (data.len < LfHeader.SIZE + cell.count * Entry.SIZE_LF) {
        return error.BufferTooSmall;
    }

    @memset(data[0..data.len], 0);

    std.mem.writeInt(u16, data[0..2], 0x6C66, .little);
    std.mem.writeInt(u16, data[2..4], cell.count, .little);

    for (0..cell.count) |i| {
        const entry_offset = LfHeader.SIZE + i * Entry.SIZE_LF;
        @memcpy(data[entry_offset..entry_offset+2], cell.entries[i].hash[0..2]);
        std.mem.writeInt(i32, data[entry_offset+2..entry_offset+6], cell.entries[i].nk_offset, .little);
    }
}

/// Serialize an LH cell
pub fn serializeLh(cell: *const LfCell, data: []u8) !void {
    if (data.len < LfHeader.SIZE + cell.count * Entry.SIZE) {
        return error.BufferTooSmall;
    }

    @memset(data[0..data.len], 0);

    std.mem.writeInt(u16, data[0..2], 0x6C68, .little);
    std.mem.writeInt(u16, data[2..4], cell.count, .little);

    for (0..cell.count) |i| {
        const entry_offset = LfHeader.SIZE + i * Entry.SIZE;
        @memcpy(data[entry_offset..entry_offset+4], cell.entries[i].hash[0..4]);
        std.mem.writeInt(i32, data[entry_offset+4..entry_offset+8], cell.entries[i].nk_offset, .little);
    }
}

/// Error types
pub const Error = error{
    BufferTooSmall,
    InvalidSignature,
    InvalidOffset,
    InvalidData,
};
