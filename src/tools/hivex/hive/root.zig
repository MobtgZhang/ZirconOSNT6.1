//! Registry Hive Library Root Module
//! 
//! This module exports all hive-related types and functions.

const std = @import("std");
const Self = @This();

/// Re-export header module
pub const Header = @import("header.zig");

/// Re-export hbin module
pub const Hbin = @import("hbin.zig");

/// Re-export cell module
pub const Cell = @import("cell.zig");

/// Re-export nk module
pub const Nk = @import("nk.zig");
pub const NkCell = Nk.NkCell;

/// Re-export vk module
pub const Vk = @import("vk.zig");

/// Re-export sk module
pub const Sk = @import("sk.zig");

/// Re-export lf module
pub const Lf = @import("lf.zig");
pub const LfCell = Lf.LfCell;

/// Re-export ri module
pub const Ri = @import("ri.zig");

/// Re-export db module
pub const Db = @import("db.zig");

/// Re-export log module
pub const Log = @import("log.zig");

/// Hive file handle
pub const Hive = struct {
    /// File handle (C FILE*)
    file: ?*anyopaque,

    /// File path
    path: []u8,

    /// Hive data (mapped or loaded)
    data: []u8,

    /// Header
    header: Header.HiveHeader,

    /// Is this hive modified
    modified: bool,

    /// Is this hive readonly
    readonly: bool,

    /// Create a new hive
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Hive {
        return Hive{
            .file = null,
            .path = try allocator.dupe(u8, path),
            .data = &.{},
            .header = Header.HiveHeader.init(),
            .modified = false,
            .readonly = false,
        };
    }

    /// Open an existing hive file
    pub fn open(path: []const u8, readonly: bool) !Hive {
        const std_libc = struct {
            extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
            extern "c" fn fread(ptr: *anyopaque, size: usize, nmemb: usize, stream: *anyopaque) usize;
            extern "c" fn fseek(stream: *anyopaque, offset: i64, whence: c_int) c_int;
            extern "c" fn ftell(stream: *anyopaque) i64;
            extern "c" fn fclose(stream: *anyopaque) c_int;
            extern "c" fn malloc(size: usize) *anyopaque;
            extern "c" fn free(ptr: *anyopaque) void;
        };
        
        const mode_bytes: [4:0]u8 = if (readonly) .{ 'r', 'b', 0, 0 } else .{ 'r', '+', 'b', 0 };
        var path_buf: [4096:0]u8 = undefined;
        @memcpy(path_buf[0..path.len], path);
        path_buf[path.len] = 0;
        
        const file_ptr = std_libc.fopen(&path_buf, &mode_bytes) orelse return error.FileNotFound;
        
        // Get file size using fseek + ftell
        _ = std_libc.fseek(file_ptr, 0, 0);  // SEEK_SET
        _ = std_libc.fseek(file_ptr, 0, 2);  // SEEK_END
        const file_size = std_libc.ftell(file_ptr);
        _ = std_libc.fseek(file_ptr, 0, 0);  // SEEK_SET - go back to start
        
        if (file_size < 0) return error.IoError;
        
        const size: usize = @intCast(file_size);
        const data_ptr = std_libc.malloc(size);
        if (@intFromPtr(data_ptr) == 0) {
            _ = std_libc.fclose(file_ptr);
            return error.OutOfMemory;
        }
        
        const read_size = std_libc.fread(data_ptr, 1, size, file_ptr);
        _ = std_libc.fclose(file_ptr);
        
        if (read_size != size) return error.IoError;
        
        const data = @as([*]u8, @ptrCast(data_ptr))[0..size];
        
        const header = try Header.HiveHeader.parse(data);
        if (!header.validate()) {
            return error.InvalidHeader;
        }

        return Hive{
            .file = null,
            .path = try std.heap.page_allocator.dupe(u8, path),
            .data = data,
            .header = header,
            .modified = false,
            .readonly = readonly,
        };
    }

    /// Create a new hive file
    pub fn create(path: []const u8, _: []const u8) !Hive {
        var data: [4096 * 2]u8 = undefined;
        @memset(&data, 0);

        var header = Header.HiveHeader.init();
        header.root_cell_offset = 4096 + 32;

        try header.serialize(&data);

        const hive = Hive{
            .file = null,
            .path = try std.heap.page_allocator.dupe(u8, path),
            .data = &data,
            .header = header,
            .modified = true,
            .readonly = false,
        };

        return hive;
    }

    /// Close the hive and flush if modified
    pub fn close(hive: *Hive) void {
        if (hive.modified and !hive.readonly) {
            hive.flush() catch {};
        }
        // Note: file is already closed after reading, data is in memory
        hive.* = undefined;
    }

    /// Flush changes to disk
    pub fn flush(hive: *Hive) !void {
        // File operations are not supported with the current implementation
        // The data is already in memory
        hive.modified = false;
    }

    /// Get the hive data
    pub fn getData(hive: *Hive) []u8 {
        return hive.data;
    }

    /// Get the header
    pub fn getHeader(hive: *Hive) *Header.HiveHeader {
        return &hive.header;
    }

    /// Get root cell offset
    pub fn getRootOffset(hive: *Hive) i32 {
        return hive.header.root_cell_offset;
    }

    /// Check if hive is modified
    pub fn isModified(hive: *const Hive) bool {
        return hive.modified;
    }

    /// Mark hive as modified
    pub fn markModified(hive: *Hive) void {
        hive.modified = true;
    }
};

/// Error types for the hive module
pub const Error = error{
    InvalidHeader,
    InvalidSignature,
    InvalidVersion,
    BufferTooSmall,
    FileNotFound,
    PermissionDenied,
    IoError,
    InvalidCell,
    CellOverflow,
    OutOfMemory,
};
