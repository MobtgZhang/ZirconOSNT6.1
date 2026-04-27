//! BCD Object Tests

const std = @import("std");
const hivex = @import("../../../src/tools/hivex/root.zig");
const testing = std.testing;

test "ObjectType values" {
    try testing.expectEqual(@as(u32, 0x01000000), @as(u32, @intFromEnum(hivex.bcd.ObjectType.FirmwareBootApplication)));
    try testing.expectEqual(@as(u32, 0x01000001), @as(u32, @intFromEnum(hivex.bcd.ObjectType.FirmwareBootManager)));
    try testing.expectEqual(@as(u32, 0x02000001), @as(u32, @intFromEnum(hivex.bcd.ObjectType.Bootmgr)));
    try testing.expectEqual(@as(u32, 0x01000010), @as(u32, @intFromEnum(hivex.bcd.ObjectType.OsLoader)));
    try testing.expectEqual(@as(u32, 0x02000004), @as(u32, @intFromEnum(hivex.bcd.ObjectType.Memdiag)));
    try testing.expectEqual(@as(u32, 0x02000005), @as(u32, @intFromEnum(hivex.bcd.ObjectType.RecoveryOs)));
}

test "ObjectType getName" {
    try testing.expectEqualSlices(u8, "OS Loader", hivex.bcd.ObjectType.OsLoader.getName());
    try testing.expectEqualSlices(u8, "Boot Manager", hivex.bcd.ObjectType.Bootmgr.getName());
    try testing.expectEqualSlices(u8, "Memory Diagnostic", hivex.bcd.ObjectType.Memdiag.getName());
    try testing.expectEqualSlices(u8, "Recovery OS", hivex.bcd.ObjectType.RecoveryOs.getName());
}

test "ObjectType isValid" {
    try testing.expect(hivex.bcd.ObjectType.OsLoader.isValid());
    try testing.expect(hivex.bcd.ObjectType.Bootmgr.isValid());
    try testing.expect(!hivex.bcd.ObjectType.Invalid.isValid());
    try testing.expect(!hivex.bcd.ObjectType.Unknown.isValid());
}

test "GUID from bytes" {
    const guid_bytes = [_]u8{
        0x78, 0x56, 0x34, 0x12,
        0x34, 0x12,
        0x34, 0x12,
        0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0
    };

    const guid = hivex.bcd.GUID.fromBytes(&guid_bytes) catch unreachable;
    try testing.expectEqual(@as(u32, 0x12345678), guid.data1);
    try testing.expectEqual(@as(u16, 0x1234), guid.data2);
    try testing.expectEqual(@as(u16, 0x1234), guid.data3);
}

test "GUID as bytes" {
    const guid = hivex.bcd.GUID{
        .data1 = 0x12345678,
        .data2 = 0x1234,
        .data3 = 0x1234,
        .data4 = .{ 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0 },
    };

    const bytes = guid.asBytes();
    try testing.expectEqual(@as(u8, 0x78), bytes[0]);
    try testing.expectEqual(@as(u8, 0x56), bytes[1]);
    try testing.expectEqual(@as(u8, 0x34), bytes[2]);
    try testing.expectEqual(@as(u8, 0x12), bytes[3]);
}

test "GUID generate" {
    const guid1 = hivex.bcd.GUID.generate();
    const guid2 = hivex.bcd.GUID.generate();

    try testing.expect(!guid1.eql(&guid2));
    try testing.expect(!guid1.isNull());
    try testing.expect(!guid2.isNull());
}

test "WellKnownGuid descriptions" {
    const guid = hivex.bcd.WellKnownGuid.getByName("bootmgr") orelse return error.TestFailed;
    const name = hivex.bcd.WellKnownGuid.getNameByGuid(&guid);
    try testing.expect(name != null);
    try testing.expectEqualSlices(u8, "bootmgr", name.?);

    const desc = hivex.bcd.WellKnownGuid.getDescriptionByGuid(&guid);
    try testing.expect(desc != null);
    try testing.expectEqualSlices(u8, "Boot Manager", desc.?);
}

test "WellKnownGuid isWellKnown" {
    const bootmgr = hivex.bcd.WellKnownGuid.getByName("bootmgr") orelse return error.TestFailed;
    try testing.expect(hivex.bcd.WellKnownGuid.isWellKnown(&bootmgr));

    const random = hivex.bcd.GUID.generate();
    try testing.expect(!hivex.bcd.WellKnownGuid.isWellKnown(&random));
}

test "BcdObject copy to new GUID" {
    const original_guid = hivex.bcd.GUID.generate();
    const new_guid = hivex.bcd.GUID.generate();

    var original = hivex.bcd.BcdObject.init(original_guid, hivex.bcd.ObjectType.OsLoader);
    original.description = try std.heap.page_allocator.dupe(u8, "Original Description");

    const elem_type: hivex.bcd.ElementType = 0x12000001;
    const elem = hivex.bcd.BcdElement.init(elem_type);
    try original.setElement(elem);

    var copy = hivex.bcd.BcdObject.init(new_guid, hivex.bcd.ObjectType.OsLoader);
    copy.description = original.description;
    try testing.expect(copy.id.eql(&new_guid));
    try testing.expect(!copy.id.eql(&original_guid));
}

test "BcdObject enumerateElements" {
    const guid = hivex.bcd.GUID.generate();
    var obj = hivex.bcd.BcdObject.init(guid, hivex.bcd.ObjectType.OsLoader);

    const elem1 = hivex.bcd.BcdElement.init(0x12000001);
    const elem2 = hivex.bcd.BcdElement.init(0x13000001);
    const elem3 = hivex.bcd.BcdElement.init(0x15000001);

    try obj.setElement(elem1);
    try obj.setElement(elem2);
    try obj.setElement(elem3);

    const elements = obj.enumerateElements();
    try testing.expectEqual(@as(usize, 3), elements.len);
}
