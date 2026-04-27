//! BCD Writer - Serialize BCD to Hive
//! 
//! Writes and serializes BCD structures to registry hive data.

const std = @import("std");
const hive = @import("../../hive/root.zig");
const object = @import("../object/root.zig");
const element = @import("../element/root.zig");
const Self = @This();

/// BCD Writer
pub const Writer = struct {
    /// Hive data buffer
    data: []u8,

    /// Current offset
    offset: usize,

    /// Cell allocator
    allocator: *CellAllocator,

    /// Create a new writer
    pub fn init(data: []u8) Writer {
        return Writer{
            .data = data,
            .offset = 4096,
            .allocator = undefined,
        };
    }

    /// Write a BCD object
    pub fn writeObject(self: *Writer, obj: *const object.Object) !void {
        _ = obj;
        _ = self;
    }

    /// Write an element
    pub fn writeElement(self: *Writer, elem: *const object.Element) !void {
        _ = elem;
        _ = self;
    }

    /// Write device element
    pub fn writeDeviceElement(self: *Writer, device: *const object.DeviceElement) !void {
        if (self.offset + 4 > self.data.len) {
            return error.BufferTooSmall;
        }
        std.mem.writeInt(u32, self.data[self.offset..self.offset+4], @as(u32, @intFromEnum(device.device_type)), .little);
        self.offset += 4;
    }

    /// Write string element
    pub fn writeStringElement(self: *Writer, str: []const u8) !void {
        if (self.offset + 2 + str.len > self.data.len) {
            return error.BufferTooSmall;
        }
        std.mem.writeInt(u16, self.data[self.offset..self.offset+2], @as(u16, @intCast(str.len)), .little);
        @memcpy(self.data[self.offset+2..self.offset+2+str.len], str);
        self.offset += 2 + str.len;
    }

    /// Write integer element
    pub fn writeIntegerElement(self: *Writer, value: u64) !void {
        if (self.offset + 8 > self.data.len) {
            return error.BufferTooSmall;
        }
        std.mem.writeInt(u64, self.data[self.offset..self.offset+8], value, .little);
        self.offset += 8;
    }

    /// Write boolean element
    pub fn writeBooleanElement(self: *Writer, value: bool) !void {
        if (self.offset + 4 > self.data.len) {
            return error.BufferTooSmall;
        }
        std.mem.writeInt(u32, self.data[self.offset..self.offset+4], if (value) 1 else 0, .little);
        self.offset += 4;
    }

    /// Write object list element
    pub fn writeObjectListElement(self: *Writer, guids: []const object.GUID) !void {
        for (guids) |guid| {
            if (self.offset + 16 > self.data.len) {
                return error.BufferTooSmall;
            }
            const bytes = guid.asBytes();
            @memcpy(self.data[self.offset..self.offset+16], &bytes);
            self.offset += 16;
        }
    }

    /// Write integer list element
    pub fn writeIntegerListElement(self: *Writer, values: []const u64) !void {
        for (values) |value| {
            if (self.offset + 8 > self.data.len) {
                return error.BufferTooSmall;
            }
            std.mem.writeInt(u64, self.data[self.offset..self.offset+8], value, .little);
            self.offset += 8;
        }
    }

    /// Allocate a cell
    pub fn allocateCell(self: *Writer, size: u32) !usize {
        const aligned_size = (size + 7) & ~@as(u32, 7);
        const offset = self.offset;
        self.offset += aligned_size;
        if (self.offset > self.data.len) {
            return error.BufferTooSmall;
        }
        return offset;
    }

    /// Update object list in hive
    pub fn updateObjectList(self: *Writer, objects: []const object.Object) !void {
        _ = objects;
        _ = self;
    }
};

/// Cell allocator (simplified)
pub const CellAllocator = struct {
    /// Allocate memory
    pub fn alloc(_: *CellAllocator, _: usize) []u8 {
        return &.{};
    }
};

/// Error types
pub const Error = error{
    BufferTooSmall,
    InvalidOffset,
    InvalidFormat,
};
