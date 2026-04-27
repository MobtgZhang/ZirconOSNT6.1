//! BCD JSON Converter
//! 
//! Converts between BCD structures and JSON format.

const std = @import("std");
const object = @import("../object/root.zig");
const element = @import("../element/root.zig");
const Self = @This();

/// BCD to JSON converter
pub const JsonWriter = struct {
    /// Output buffer
    buf: std.ArrayList(u8),
    
    /// Allocator
    allocator: std.mem.Allocator,

    /// Indent level
    indent: usize,

    /// Create a new JSON writer
    pub fn init(allocator: std.mem.Allocator) !JsonWriter {
        return JsonWriter{
            .buf = try std.ArrayList(u8).initCapacity(allocator, 4096),
            .allocator = allocator,
            .indent = 0,
        };
    }

    /// Write the beginning of an object
    pub fn beginObject(self: *JsonWriter) !void {
        try self.buf.append(self.allocator, '{');
        self.indent += 1;
    }

    /// Write the end of an object
    pub fn endObject(self: *JsonWriter) !void {
        self.indent -= 1;
        try self.buf.append(self.allocator, '}');
    }

    /// Write a string key-value pair
    pub fn writeKeyValue(self: *JsonWriter, key: []const u8, value: []const u8) !void {
        try self.buf.append(self.allocator, ',');
        try self.writeString(key);
        try self.buf.append(self.allocator, ':');
        try self.writeString(value);
    }

    /// Write a string value
    pub fn writeString(self: *JsonWriter, str: []const u8) !void {
        try self.buf.append(self.allocator, '"');
        for (str) |c| {
            switch (c) {
                '"' => { try self.buf.appendSlice(self.allocator, "\\\""); },
                '\\' => { try self.buf.appendSlice(self.allocator, "\\\\"); },
                '\n' => { try self.buf.appendSlice(self.allocator, "\\n"); },
                '\r' => { try self.buf.appendSlice(self.allocator, "\\r"); },
                '\t' => { try self.buf.appendSlice(self.allocator, "\\t"); },
                else => { try self.buf.append(self.allocator, c); },
            }
        }
        try self.buf.append(self.allocator, '"');
    }

    /// Write an integer value
    pub fn writeInteger(self: *JsonWriter, value: u64) !void {
        var buf: [32]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
        try self.buf.appendSlice(self.allocator, str);
    }

    /// Write a boolean value
    pub fn writeBoolean(self: *JsonWriter, value: bool) !void {
        const str = if (value) "true" else "false";
        try self.buf.appendSlice(self.allocator, str);
    }

    /// Write a GUID value
    pub fn writeGuid(self: *JsonWriter, guid: *const object.GUID) !void {
        var buf: [38]u8 = undefined;
        _ = guid.formatStatic(&buf);
        try self.buf.appendSlice(self.allocator, buf[0..38]);
    }

    /// Convert object to JSON
    pub fn writeObject(self: *JsonWriter, obj: *const object.Object) !void {
        try self.beginObject();
        try self.buf.appendSlice(self.allocator, "\n");

        try self.writeInteger(@as(u64, 0)); // placeholder
        _ = self.buf.pop();
        try self.writeGuid(&obj.id);
        try self.buf.append(self.allocator, ',');
        try self.buf.append(self.allocator, '\n');

        _ = obj.object_type.getName();
        try self.writeString("type");

        if (obj.elements.items.len > 0) {
            try self.buf.append(self.allocator, ',');
            try self.buf.append(self.allocator, '\n');
            try self.buf.appendSlice(self.allocator, "\"elements\": [\n");

            for (obj.elements.items, 0..) |elem, i| {
                if (i > 0) {
                    try self.buf.append(self.allocator, ',');
                }
                try self.writeElement(elem);
            }

            try self.buf.append(self.allocator, '\n');
            try self.buf.append(self.allocator, ']');
        }

        try self.buf.append(self.allocator, '\n');
        try self.endObject();
    }

    /// Write element to JSON
    pub fn writeElement(self: *JsonWriter, elem: *const object.Element) !void {
        const type_val: u32 = @intFromEnum(elem.element_type);
        var buf: [64]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "{{\"type\": 0x{x}, \"data\": \"...\"}}", .{type_val}) catch return;
        try self.buf.appendSlice(self.allocator, str);
    }

    /// Get the JSON output
    pub fn getOutput(self: *JsonWriter) []u8 {
        return self.buf.items;
    }

    /// Deinitialize
    pub fn deinit(self: *JsonWriter) void {
        self.buf.deinit(self.allocator);
    }
};

/// JSON to BCD converter
pub const JsonReader = struct {
    /// JSON data
    data: []const u8,

    /// Current position
    pos: usize,

    /// Allocator
    allocator: std.mem.Allocator,

    /// Create a new JSON reader
    pub fn init(allocator: std.mem.Allocator, data: []const u8) JsonReader {
        return JsonReader{
            .data = data,
            .pos = 0,
            .allocator = allocator,
        };
    }

    /// Skip whitespace
    fn skipWhitespace(self: *JsonReader) void {
        while (self.pos < self.data.len and std.ascii.isWhitespace(self.data[self.pos])) {
            self.pos += 1;
        }
    }

    /// Read a JSON string
    fn readString(self: *JsonReader) ![]u8 {
        self.skipWhitespace();
        if (self.pos >= self.data.len or self.data[self.pos] != '"') {
            return error.InvalidFormat;
        }
        self.pos += 1;

        var result = std.ArrayList(u8).empty;
        while (self.pos < self.data.len and self.data[self.pos] != '"') {
            const c = self.data[self.pos];
            if (c == '\\') {
                self.pos += 1;
                if (self.pos < self.data.len) {
                    switch (self.data[self.pos]) {
                        '"' => { try result.append(self.allocator, '"'); },
                        '\\' => { try result.append(self.allocator, '\\'); },
                        'n' => { try result.append(self.allocator, '\n'); },
                        'r' => { try result.append(self.allocator, '\r'); },
                        't' => { try result.append(self.allocator, '\t'); },
                        else => { try result.append(self.allocator, self.data[self.pos]); },
                    }
                }
            } else {
                try result.append(self.allocator, c);
            }
            self.pos += 1;
        }

        if (self.pos < self.data.len) {
            self.pos += 1;
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Read an object from JSON
    pub fn readObject(self: *JsonReader) !object.Object {
        self.skipWhitespace();
        if (self.pos >= self.data.len or self.data[self.pos] != '{') {
            return error.InvalidFormat;
        }
        self.pos += 1;

        // Skip parsing for now - just return a placeholder
        while (self.pos < self.data.len and self.data[self.pos] != '}') {
            self.pos += 1;
        }
        if (self.pos < self.data.len) {
            self.pos += 1;
        }

        return object.Object.init(object.GUID.zero(), object.ObjectType.Application);
    }

    /// Read a BCD store from JSON
    pub fn readStore(self: *JsonReader) ![]object.Object {
        self.skipWhitespace();
        if (self.pos >= self.data.len or self.data[self.pos] != '[') {
            return error.InvalidFormat;
        }
        self.pos += 1;

        var objects = std.ArrayList(object.Object).empty;

        while (self.pos < self.data.len) {
            self.skipWhitespace();
            if (self.data[self.pos] == ']') {
                self.pos += 1;
                break;
            }

            const obj = self.readObject() catch continue;
            try objects.append(self.allocator, obj);

            self.skipWhitespace();
            if (self.pos < self.data.len and self.data[self.pos] == ',') {
                self.pos += 1;
            }
        }

        return objects.toOwnedSlice(self.allocator);
    }

    /// Error types
    pub const Error = error{
        InvalidFormat,
        UnexpectedEndOfFile,
    };
};
