//! BCD Text Formatter
//! 
//! Formats BCD structures as human-readable text (similar to bcdedit).

const std = @import("std");
const object = @import("../object/root.zig");
const element = @import("../element/root.zig");
const Self = @This();

/// Output format
pub const Format = enum {
    /// bcdedit-style output
    Bcdedit,
    /// Detailed output
    Detailed,
    /// Compact output
    Compact,
};

/// BCD Text Writer
pub const TextWriter = struct {
    /// Output buffer
    buf: std.ArrayList(u8),
    
    /// Allocator
    allocator: std.mem.Allocator,

    /// Format
    format: Format,

    /// Use colors
    use_color: bool,

    /// Create a new text writer
    pub fn init(allocator: std.mem.Allocator, format: Format) !TextWriter {
        const buf = try std.ArrayList(u8).initCapacity(allocator, 4096);
        return TextWriter{
            .buf = buf,
            .allocator = allocator,
            .format = format,
            .use_color = false,
        };
    }

    /// Enable/disable colors
    pub fn setColor(self: *TextWriter, enabled: bool) void {
        self.use_color = enabled;
    }

    /// Write a line
    pub fn writeLine(self: *TextWriter, line: []const u8) !void {
        for (line) |c| {
            try self.buf.append(self.allocator, c);
        }
        try self.buf.append(self.allocator, '\n');
    }
    
    /// Write header
    pub fn writeHeader(self: *TextWriter, title: []const u8) !void {
        try self.appendStr("=== ");
        try self.appendStr(title);
        try self.appendStr(" ===\n");
    }

    /// Write separator
    pub fn writeSeparator(self: *TextWriter) !void {
        try self.appendStr("------------------------------------------------\n");
    }

    /// Append a string to the buffer
    fn appendStr(self: *TextWriter, str: []const u8) !void {
        for (str) |c| {
            try self.buf.append(self.allocator, c);
        }
    }

    /// Format GUID to static buffer
    fn guidToString(self: *TextWriter, guid: *const object.GUID) ![38]u8 {
        _ = self;
        var buf: [38]u8 = undefined;
        guid.formatStatic(&buf);
        return buf;
    }

    /// Format object type
    pub fn formatType(self: *TextWriter, obj_type: object.ObjectType) []const u8 {
        _ = self;
        return obj_type.getName();
    }

    /// Write an object
    pub fn writeObject(self: *TextWriter, obj: *const object.Object) !void {
        switch (self.format) {
            .Bcdedit => try self.writeObjectBcdedit(obj),
            .Detailed => try self.writeObjectDetailed(obj),
            .Compact => try self.writeObjectCompact(obj),
        }
    }

    /// Write store header
    pub fn writeStoreHeader(self: *TextWriter, path: []const u8, count: usize) !void {
        try self.appendStr("BCD Store: ");
        try self.appendStr(path);
        try self.appendStr("\nObject count: ");
        
        var num_buf: [32]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{count}) catch "";
        try self.appendStr(num_str);
        try self.appendStr("\n\n");
    }

    /// Write object in bcdedit style
    fn writeObjectBcdedit(self: *TextWriter, obj: *const object.Object) !void {
        const guid_buf = try self.guidToString(&obj.id);
        
        try self.appendStr("identifier {");
        try self.appendStr(&guid_buf);
        try self.appendStr("}\n");
        
        const type_name = obj.object_type.getName();
        try self.appendStr("type               ");
        try self.appendStr(type_name);
        try self.appendStr("\n");
        
        if (obj.description.len > 0) {
            try self.appendStr("description        ");
            try self.appendStr(obj.description);
            try self.appendStr("\n");
        }
        
        try self.appendStr("\n");
    }

    /// Write object in detailed style
    fn writeObjectDetailed(self: *TextWriter, obj: *const object.Object) !void {
        try self.writeSeparator();
        
        const guid_buf = try self.guidToString(&obj.id);
        
        try self.appendStr("Object GUID: {");
        try self.appendStr(&guid_buf);
        try self.appendStr("}\n");
        
        try self.appendStr("Type: ");
        try self.appendStr(obj.object_type.getName());
        try self.appendStr("\n");
        
        if (obj.description.len > 0) {
            try self.appendStr("Description: ");
            try self.appendStr(obj.description);
            try self.appendStr("\n");
        }
        
        try self.appendStr("\n");
    }

    /// Write object in compact style
    fn writeObjectCompact(self: *TextWriter, obj: *const object.Object) !void {
        const guid_buf = try self.guidToString(&obj.id);
        
        try self.appendStr("{");
        try self.appendStr(&guid_buf);
        try self.appendStr("} ");
        try self.appendStr(obj.object_type.getName());
        
        if (obj.description.len > 0) {
            try self.appendStr(" - ");
            try self.appendStr(obj.description);
        }
        
        try self.appendStr("\n");
    }

    /// Get the output
    pub fn getOutput(self: *TextWriter) []u8 {
        return self.buf.items;
    }

    /// Deinitialize
    pub fn deinit(self: *TextWriter) void {
        self.buf.deinit(self.allocator);
    }
};
