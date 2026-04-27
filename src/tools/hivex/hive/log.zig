//! Registry Hive Transaction Log
//! 
//! Windows Registry uses transaction logs (.LOG1/.LOG2) for recovery.
//! This module handles parsing and replaying of transaction logs.

const std = @import("std");
const Self = @This();

/// Log file signature
pub const LOG1_SIGNATURE: [4]u8 = .{ 'h', 'l', 'o', 'g' };
pub const LOG2_SIGNATURE: [4]u8 = .{ 'h', 'l', 'o', 'g' };

/// Log record types
pub const RecordType = enum(u32) {
    /// Log file header
    header = 0x00000001,
    /// New hive
    new_hive = 0x00000002,
    /// Base block
    base_block = 0x00000003,
    /// Dirty page
    dirty_page = 0x00000004,
    /// Dirty table
    dirty_table = 0x00000005,
    /// Dirty bucket
    dirty_bucket = 0x00000006,
};

/// Log file header
pub const LogHeader = extern struct {
    /// "hlog" signature (4 bytes)
    signature: [4]u8,

    /// Sequence number (4 bytes)
    sequence_number: u32,

    /// Log file version (4 bytes)
    version: u32,

    /// Header size (4 bytes)
    header_size: u32,

    /// Offset to dirty page table (4 bytes)
    dirty_page_offset: u32,

    /// Offset to second section (4 bytes)
    second_section_offset: u32,

    /// Log file size (4 bytes)
    log_size: u32,

    /// Checksum (4 bytes)
    checksum: u32,

    /// Header size
    pub const SIZE: usize = 36;
};

/// Dirty page record
pub const DirtyPage = struct {
    /// Offset to page in hive file (4 bytes)
    hive_offset: u32,

    /// Size of page (4 bytes)
    size: u32,

    /// Sequence number (8 bytes)
    sequence_number: u64,
};

/// Dirty table record
pub const DirtyTable = struct {
    /// Base offset (4 bytes)
    base_offset: u32,

    /// Number of dirty cells (4 bytes)
    cell_count: u32,

    /// Offsets to dirty cells (variable)
    cell_offsets: []u32,
};

/// Log record header
pub const RecordHeader = extern struct {
    /// Record type (4 bytes)
    record_type: u32,

    /// Record size (4 bytes)
    size: u32,

    /// Record size
    pub const SIZE: usize = 8;
};

/// Transaction log state
pub const LogState = struct {
    /// Log file path
    path: []const u8,

    /// Current sequence number
    sequence_number: u32,

    /// Log file size
    log_size: u32,

    /// Is LOG1 (false = LOG2)
    is_log1: bool,

    /// Dirty pages
    dirty_pages: std.ArrayList(DirtyPage),

    /// Dirty tables
    dirty_tables: std.ArrayList(DirtyTable),

    /// Raw log data
    raw_data: []const u8,
};

/// Hive log manager
pub const HiveLog = struct {
    /// Log file path
    path: []u8,

    /// LOG1 exists
    log1_exists: bool,

    /// LOG2 exists
    log2_exists: bool,

    /// Current sequence number
    sequence_number: u32,

    /// Dirty pages for replay
    dirty_pages: std.ArrayList(DirtyPage),

    /// Dirty tables for replay
    dirty_tables: std.ArrayList(DirtyTable),

    /// Parse log file header
    pub fn parseHeader(data: []const u8) !LogHeader {
        if (data.len < LogHeader.SIZE) {
            return error.BufferTooSmall;
        }

        if (!std.mem.eql(u8, data[0..4], LOG1_SIGNATURE) and
            !std.mem.eql(u8, data[0..4], LOG2_SIGNATURE)) {
            return error.InvalidSignature;
        }

        return LogHeader{
            .signature = data[0..4].*,
            .sequence_number = std.mem.readInt(u32, data[4..8], .little),
            .version = std.mem.readInt(u32, data[8..12], .little),
            .header_size = std.mem.readInt(u32, data[12..16], .little),
            .dirty_page_offset = std.mem.readInt(u32, data[16..20], .little),
            .second_section_offset = std.mem.readInt(u32, data[20..24], .little),
            .log_size = std.mem.readInt(u32, data[24..28], .little),
            .checksum = std.mem.readInt(u32, data[28..32], .little),
        };
    }

    /// Parse dirty page table
    pub fn parseDirtyPages(data: []const u8, offset: u32) ![]DirtyPage {
        if (data.len < offset + 4) {
            return error.BufferTooSmall;
        }

        const count = std.mem.readInt(u32, data[offset..offset+4], .little);
        var pages: [1024]DirtyPage = undefined;
        var valid_count: usize = 0;

        for (0..count) |i| {
            const off = offset + 4 + i * @sizeOf(DirtyPage);
            if (off + @sizeOf(DirtyPage) > data.len) break;

            pages[i] = DirtyPage{
                .hive_offset = std.mem.readInt(u32, data[off..off+4], .little),
                .size = std.mem.readInt(u32, data[off+4..off+8], .little),
                .sequence_number = std.mem.readInt(u64, data[off+8..off+16], .little),
            };
            valid_count += 1;
        }

        return pages[0..valid_count];
    }

    /// Parse dirty table
    pub fn parseDirtyTable(data: []const u8, offset: u32) !DirtyTable {
        if (data.len < offset + 8) {
            return error.BufferTooSmall;
        }

        const base_offset = std.mem.readInt(u32, data[offset..offset+4], .little);
        const cell_count = std.mem.readInt(u32, data[offset+4..offset+8], .little);

        var cell_offsets: [256]u32 = undefined;
        for (0..@min(cell_count, 256)) |i| {
            const off = offset + 8 + i * 4;
            if (off + 4 > data.len) break;
            cell_offsets[i] = std.mem.readInt(u32, data[off..off+4], .little);
        }

        return DirtyTable{
            .base_offset = base_offset,
            .cell_count = cell_count,
            .cell_offsets = cell_offsets[0..@min(cell_count, 256)],
        };
    }

    /// Compute log file checksum
    pub fn computeChecksum(data: []const u8) u32 {
        var sum: u32 = 0;
        for (data[0..28]) |byte| {
            sum = (sum >> 31) | (sum << 1);
            sum +%= byte;
        }
        return sum;
    }

    /// Validate log file checksum
    pub fn validateChecksum(header: *const LogHeader, data: []const u8) bool {
        return header.checksum == computeChecksum(data);
    }

    /// Replay log to hive data
    pub fn replay(log: *const HiveLog, hive_data: []u8) !void {
        for (log.dirty_pages.items) |page| {
            if (page.hive_offset + page.size > hive_data.len) {
                return error.InvalidOffset;
            }
        }

        for (log.dirty_tables.items) |table| {
            const base = @as(usize, @intCast(table.base_offset));
            for (table.cell_offsets[0..table.cell_count]) |cell_off| {
                const offset = base + @as(usize, @intCast(cell_off));
                if (offset + 4 > hive_data.len) continue;
                const cell_size = @as(i32, @bitCast(std.mem.readInt(u32, hive_data[offset..offset+4], .little)));
                if (cell_size < 0) {
                    const abs_size = @as(u32, @intCast(@abs(cell_size)));
                    @memset(hive_data[offset..offset + abs_size], 0);
                }
            }
        }
    }

    /// Create new log manager
    pub fn init(allocator: std.mem.Allocator) HiveLog {
        return HiveLog{
            .path = &.{},
            .log1_exists = false,
            .log2_exists = false,
            .sequence_number = 0,
            .dirty_pages = std.ArrayList(DirtyPage).init(allocator),
            .dirty_tables = std.ArrayList(DirtyTable).init(allocator),
        };
    }

    /// Deinitialize
    pub fn deinit(log: *HiveLog) void {
        log.dirty_pages.deinit();
        log.dirty_tables.deinit();
    }

    /// Get last sequence number from logs
    pub fn getLastSequence(log: *const HiveLog) u32 {
        return log.sequence_number;
    }

    /// Check if logs need replay
    pub fn needsReplay(log: *const HiveLog) bool {
        return log.log1_exists or log.log2_exists;
    }
};

/// Error types
pub const Error = error{
    BufferTooSmall,
    InvalidSignature,
    InvalidVersion,
    InvalidChecksum,
    InvalidOffset,
    InvalidData,
    LogCorrupt,
};
