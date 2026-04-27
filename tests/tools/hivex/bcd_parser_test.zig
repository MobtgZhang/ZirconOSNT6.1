//! BCD Parser Tests

const std = @import("std");
const hivex = @import("../../../src/tools/hivex/root.zig");
const testing = std.testing;

test "TextWriter init" {
    var writer = hivex.bcd.BcdTextWriter.init(std.heap.page_allocator, .Bcdedit);
    defer writer.deinit();

    const output = writer.getOutput();
    try testing.expectEqual(@as(usize, 0), output.len);
}

test "TextWriter writeHeader" {
    var writer = hivex.bcd.BcdTextWriter.init(std.heap.page_allocator, .Bcdedit);
    defer writer.deinit();

    try writer.writeHeader("Test Header");
    const output = writer.getOutput();
    try testing.expect(std.mem.indexOf(u8, output, "=== Test Header ===") != null);
}

test "TextWriter writeSeparator" {
    var writer = hivex.bcd.BcdTextWriter.init(std.heap.page_allocator, .Bcdedit);
    defer writer.deinit();

    try writer.writeSeparator();
    const output = writer.getOutput();
    try testing.expectEqual(@as(usize, 53), output.len);
}

test "TextWriter formatType" {
    var writer = hivex.bcd.BcdTextWriter.init(std.heap.page_allocator, .Bcdedit);
    defer writer.deinit();

    const type_name = writer.formatType(hivex.bcd.ObjectType.OsLoader);
    try testing.expectEqualSlices(u8, "OS Loader", type_name);
}

test "TextWriter writeStoreHeader" {
    var writer = hivex.bcd.BcdTextWriter.init(std.heap.page_allocator, .Bcdedit);
    defer writer.deinit();

    try writer.writeStoreHeader("C:\\boot\\bcd", 10);
    const output = writer.getOutput();
    try testing.expect(std.mem.indexOf(u8, output, "C:\\boot\\bcd") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Objects: 10") != null);
}

test "TextWriter format types" {
    var bcdedit_writer = hivex.bcd.BcdTextWriter.init(std.heap.page_allocator, .Bcdedit);
    var detailed_writer = hivex.bcd.BcdTextWriter.init(std.heap.page_allocator, .Detailed);
    var compact_writer = hivex.bcd.BcdTextWriter.init(std.heap.page_allocator, .Compact);

    try bcdedit_writer.writeHeader("BCD");
    try detailed_writer.writeHeader("BCD");
    try compact_writer.writeHeader("BCD");

    const bcdedit_out = bcdedit_writer.getOutput();
    const detailed_out = detailed_writer.getOutput();
    const compact_out = compact_writer.getOutput();

    try testing.expect(bcdedit_out.len > 0);
    try testing.expect(detailed_out.len > 0);
    try testing.expect(compact_out.len > 0);
}

test "TextWriter color" {
    var writer = hivex.bcd.BcdTextWriter.init(std.heap.page_allocator, .Bcdedit);
    defer writer.deinit();

    try testing.expect(!writer.use_color);
    writer.setColor(true);
    try testing.expect(writer.use_color);
    writer.setColor(false);
    try testing.expect(!writer.use_color);
}

test "JsonWriter init" {
    var writer = hivex.bcd.BcdJsonWriter.init(std.heap.page_allocator);
    defer writer.deinit();

    try writer.beginObject();
    try writer.endObject();

    const output = writer.getOutput();
    try testing.expectEqualSlices(u8, "{}", output);
}

test "JsonWriter writeKeyValue" {
    var writer = hivex.bcd.BcdJsonWriter.init(std.heap.page_allocator);
    defer writer.deinit();

    try writer.beginObject();
    try writer.writeKeyValue("key", "value");
    try writer.endObject();

    const output = writer.getOutput();
    try testing.expect(std.mem.indexOf(u8, output, "\"key\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"value\"") != null);
}

test "JsonWriter writeInteger" {
    var writer = hivex.bcd.BcdJsonWriter.init(std.heap.page_allocator);
    defer writer.deinit();

    try writer.beginObject();
    try writer.buf.appendSlice("\"number\": ");
    try writer.writeInteger(42);
    try writer.endObject();

    const output = writer.getOutput();
    try testing.expect(std.mem.indexOf(u8, output, "42") != null);
}

test "JsonWriter writeBoolean" {
    var writer = hivex.bcd.BcdJsonWriter.init(std.heap.page_allocator);
    defer writer.deinit();

    try writer.beginObject();
    try writer.buf.appendSlice("\"flag\": ");
    try writer.writeBoolean(true);
    try writer.endObject();

    const output = writer.getOutput();
    try testing.expect(std.mem.indexOf(u8, output, "true") != null);
}

test "JsonWriter writeGuid" {
    var writer = hivex.bcd.BcdJsonWriter.init(std.heap.page_allocator);
    defer writer.deinit();

    const guid = hivex.bcd.GUID{
        .data1 = 0x12345678,
        .data2 = 0x1234,
        .data3 = 0x1234,
        .data4 = .{0} ** 8,
    };

    try writer.beginObject();
    try writer.buf.appendSlice("\"guid\": ");
    try writer.writeGuid(&guid);
    try writer.endObject();

    const output = writer.getOutput();
    try testing.expect(std.mem.indexOf(u8, output, "12345678") != null);
}

test "JsonReader init" {
    const json_data = "{}";
    var reader = hivex.bcd.BcdJsonReader.init(json_data);
    try reader.skipWhitespace();
    try testing.expectEqual(@as(u8, '{'), reader.data[reader.pos]);
}

test "JsonReader readString" {
    const json_data = "\"test string\"";
    var reader = hivex.bcd.BcdJsonReader.init(json_data);

    const str = try reader.readString();
    try testing.expectEqualSlices(u8, "test string", str);
}

test "JsonReader readObject" {
    const json_data = "{\"guid\": \"{12345678-1234-1234-1234-123456789abc}\"}";
    var reader = hivex.bcd.BcdJsonReader.init(json_data);

    const obj = try reader.readObject();
    try testing.expect(!obj.id.isNull());
}

test "BcdReader init" {
    var data: [4096]u8 = undefined;
    @memset(&data, 0);

    const reader = hivex.bcd.BcdReader.init(&data, 4096);
    try testing.expectEqual(@as(usize, 4096), @as(usize, @intCast(reader.root_offset)));
}

test "BcdReader validate" {
    var data: [4096]u8 = undefined;
    @memset(&data, 0);

    var reader = hivex.bcd.BcdReader.init(&data, 4096);
    const valid = try reader.validate();
    try testing.expect(!valid);
}
