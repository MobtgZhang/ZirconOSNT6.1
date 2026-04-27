//! BCD Reader - Parse BCD from Hive
//! 
//! Reads and deserializes BCD structures from registry hive data.

const std = @import("std");
const hive = @import("../../hive/root.zig");
const object = @import("../object/root.zig");
const element = @import("../element/root.zig");
const Self = @This();

/// BCD Reader
pub const Reader = struct {
    /// Hive data
    hive_data: []const u8,

    /// Root offset
    root_offset: i32,
    
    /// Allocator
    allocator: std.mem.Allocator,
    
    /// Objects read
    objects: std.ArrayList(object.Object),

    /// Create a new reader
    pub fn init(hive_data: []const u8, root_offset: i32) !Reader {
        return Reader{
            .hive_data = hive_data,
            .root_offset = root_offset,
            .allocator = std.heap.page_allocator,
            .objects = try std.ArrayList(object.Object).initCapacity(std.heap.page_allocator, 128),
        };
    }

    /// Read the BCD object list from the root
    pub fn readObjectList(self: *Reader) !void {
        // BCD GUIDs are stored as ASCII strings in the hive
        // Format: {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}
        // Each GUID is 38 characters long
        
        // Simple deduplication: track up to 1000 GUIDs
        var found_guids: [1000][38]u8 = undefined;
        var found_count: usize = 0;
        
        var offset: usize = 0;
        while (offset < self.hive_data.len - 38) {
            // Look for ASCII '{' character (0x7B)
            if (self.hive_data[offset] == '{') {
                // Try to parse as GUID (exactly 38 chars including braces)
                const slice = self.hive_data[offset..offset + 38];
                
                // Check if it looks like a valid GUID
                if (isValidGuidFormat(slice)) {
                    // Parse using the object's GUID.parse
                    const guid = object.GUID.parse(slice) catch continue;
                    
                    // Check for duplicates
                    var guid_buf: [38]u8 = undefined;
                    guid.formatStatic(&guid_buf);
                    
                    var is_duplicate = false;
                    for (0..found_count) |i| {
                        if (std.mem.eql(u8, &found_guids[i], &guid_buf)) {
                            is_duplicate = true;
                            break;
                        }
                    }
                    
                    if (!is_duplicate and found_count < 1000) {
                        found_guids[found_count] = guid_buf;
                        found_count += 1;
                        
                        const obj = object.Object.init(guid, object.ObjectType.OsLoader);
                        try self.objects.append(self.allocator, obj);
                    }
                    
                    // Skip past this GUID to avoid duplicate matches
                    offset += 38;
                    continue;
                }
            }
            offset += 1;
        }
    }
    
    /// Check if a string looks like a valid GUID format
    fn isValidGuidFormat(str: []const u8) bool {
        if (str.len < 38) return false;
        
        // Must start with '{' and end with '}'
        if (str[0] != '{' or str[37] != '}') return false;
        
        // Check dashes at positions 9, 14, 19, 24
        if (str[9] != '-' or str[14] != '-' or str[19] != '-' or str[24] != '-') return false;
        
        // All other characters must be hex digits
        var i: usize = 1;
        while (i < 37) : (i += 1) {
            if (i == 9 or i == 14 or i == 19 or i == 24) continue; // Skip dashes
            const c = str[i];
            if ((c < '0' or c > '9') and (c < 'a' or c > 'f') and (c < 'A' or c > 'F')) {
                return false;
            }
        }
        
        return true;
    }

    /// Read a single BCD object
    pub fn readObject(self: *Reader, nk_data: []const u8) !object.Object {
        const nk_cell = try hive.NkCell.parse(nk_data);
        
        // Try to extract GUID from SK cell
        var guid: object.GUID = undefined;
        guid.data1 = 0;
        guid.data2 = 0;
        guid.data3 = 0;
        guid.data4 = .{0} ** 8;
        
        if (nk_cell.sk_offset != 0) {
            const nk_offset_abs = self.hive_data.len - nk_data.len;
            const sk_offset_abs = @as(usize, @intCast(@as(i32, @intCast(nk_offset_abs)) + nk_cell.sk_offset));
            if (sk_offset_abs < self.hive_data.len and sk_offset_abs + 32 < self.hive_data.len) {
                const sk_data = self.hive_data[sk_offset_abs..];
                // SK signature is at offset 0
                if (sk_data[0] == 's' and sk_data[1] == 'k') {
                    // GUID is at bytes 8-24 in the SK cell
                    guid.data1 = std.mem.readInt(u32, sk_data[8..12], .little);
                    guid.data2 = std.mem.readInt(u16, sk_data[12..14], .little);
                    guid.data3 = std.mem.readInt(u16, sk_data[14..16], .little);
                    @memcpy(guid.data4[0..], sk_data[16..24]);
                }
            }
        }

        const obj = object.Object.init(guid, object.ObjectType.OsLoader);
        return obj;
    }

    /// Read an element
    pub fn readElement(_: *Reader, element_data: []const u8) !object.Element {
        _ = element_data;
        const elem = object.Element.init(0);
        return elem.*;
    }

    /// Read device element
    pub fn readDeviceElement(_: *Reader, data: []const u8) !object.DeviceElement {
        var device = object.DeviceElement.init();
        if (data.len >= 4) {
            const device_type = std.mem.readInt(u32, data[0..4], .little);
            device.device_type = @as(object.DeviceType, @enumFromInt(device_type));
        }
        return device;
    }

    /// Read string element
    pub fn readStringElement(_: *Reader, data: []const u8) ![]u8 {
        if (data.len < 2) return error.InvalidData;
        const len = std.mem.readInt(u16, data[0..2], .little);
        if (data.len < 2 + len) return error.BufferTooSmall;
        return @constCast(data[2..2+len]);
    }

    /// Read integer element
    pub fn readIntegerElement(_: *Reader, data: []const u8) !u64 {
        if (data.len < 8) return error.BufferTooSmall;
        return std.mem.readInt(u64, data[0..8], .little);
    }

    /// Read boolean element
    pub fn readBooleanElement(_: *Reader, data: []const u8) !bool {
        if (data.len < 4) return error.BufferTooSmall;
        return std.mem.readInt(u32, data[0..4], .little) != 0;
    }

    /// Read object list element
    pub fn readObjectListElement(_: *Reader, data: []const u8) !std.ArrayList(object.GUID) {
        var guids = try std.ArrayList(object.GUID).initCapacity(std.heap.page_allocator, 16);
        var offset: usize = 0;

        while (offset + 16 <= data.len) {
            const guid = try object.GUID.fromBytes(data[offset..offset+16]);
            try guids.append(std.heap.page_allocator, guid);
            offset += 16;
        }

        return guids;
    }

    /// Read integer list element
    pub fn readIntegerListElement(_: *Reader, data: []const u8) !std.ArrayList(u64) {
        var values = try std.ArrayList(u64).initCapacity(std.heap.page_allocator, 16);
        var offset: usize = 0;

        while (offset + 8 <= data.len) {
            const value = std.mem.readInt(u64, data[offset..offset+8], .little);
            try values.append(std.heap.page_allocator, value);
            offset += 8;
        }

        return values;
    }

    /// Validate BCD structure
    pub fn validate(self: *Reader) !void {
        if (self.hive_data.len < 4096) {
            return error.BufferTooSmall;
        }
        
        const nk_data = self.hive_data[@as(usize, @intCast(self.root_offset))..];
        _ = try hive.NkCell.parse(nk_data);
    }

    /// Error types
    pub const Error = error{
        InvalidData,
        BufferTooSmall,
        InvalidOffset,
    };
};
