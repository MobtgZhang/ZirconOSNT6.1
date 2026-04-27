//! BCD Element Tests

const std = @import("std");
const hivex = @import("../../../src/tools/hivex/root.zig");
const testing = std.testing;

test "ElementType categories" {
    try testing.expectEqual(.Device, hivex.bcd.ElementType.getCategory(0x11000001));
    try testing.expectEqual(.Integer, hivex.bcd.ElementType.getCategory(0x12000001));
    try testing.expectEqual(.Boolean, hivex.bcd.ElementType.getCategory(0x13000001));
    try testing.expectEqual(.String, hivex.bcd.ElementType.getCategory(0x15000001));
    try testing.expectEqual(.ObjectList, hivex.bcd.ElementType.getCategory(0x17000001));
    try testing.expectEqual(.Object, hivex.bcd.ElementType.getCategory(0x19000001));
}

test "ElementType isDevice" {
    try testing.expect(hivex.bcd.ElementType.isDevice(0x11000001));
    try testing.expect(!hivex.bcd.ElementType.isDevice(0x12000001));
}

test "ElementType isInteger" {
    try testing.expect(hivex.bcd.ElementType.isInteger(0x12000001));
    try testing.expect(!hivex.bcd.ElementType.isInteger(0x11000001));
}

test "ElementType isBoolean" {
    try testing.expect(hivex.bcd.ElementType.isBoolean(0x13000001));
    try testing.expect(!hivex.bcd.ElementType.isBoolean(0x12000001));
}

test "ElementType isString" {
    try testing.expect(hivex.bcd.ElementType.isString(0x15000001));
    try testing.expect(!hivex.bcd.ElementType.isString(0x13000001));
}

test "ElementType getName" {
    const name = hivex.bcd.ElementType.getName(0x11000001);
    try testing.expect(name != null);
    try testing.expectEqualSlices(u8, "Device Description", name.?);

    const timeout_name = hivex.bcd.ElementType.getName(0x12000001);
    try testing.expect(timeout_name != null);
    try testing.expectEqualSlices(u8, "Timeout", timeout_name.?);
}

test "ElementType common constants" {
    try testing.expectEqual(@as(hivex.bcd.ElementType, 0x11000001), hivex.bcd.ElementType.Common.DEVICE_DESCRIPTION);
    try testing.expectEqual(@as(hivex.bcd.ElementType, 0x12000001), hivex.bcd.ElementType.Common.TIMEOUT);
    try testing.expectEqual(@as(hivex.bcd.ElementType, 0x13000001), hivex.bcd.ElementType.Common.BOOT_LOGO);
    try testing.expectEqual(@as(hivex.bcd.ElementType, 0x15000001), hivex.bcd.ElementType.Common.BOOT_MENU_TEXT);
    try testing.expectEqual(@as(hivex.bcd.ElementType, 0x17000001), hivex.bcd.ElementType.Common.BOOT_SEQUENCE_OBJECT_LIST);
    try testing.expectEqual(@as(hivex.bcd.ElementType, 0x19000001), hivex.bcd.ElementType.Common.INHERITED_OBJECTS);
}

test "DeviceType values" {
    try testing.expectEqual(@as(u32, 0x00000000), @as(u32, @intFromEnum(hivex.bcd.DeviceType.None)));
    try testing.expectEqual(@as(u32, 0x10000001), @as(u32, @intFromEnum(hivex.bcd.DeviceType.BootDevice)));
    try testing.expectEqual(@as(u32, 0x20000001), @as(u32, @intFromEnum(hivex.bcd.DeviceType.Partition)));
    try testing.expectEqual(@as(u32, 0x20000003), @as(u32, @intFromEnum(hivex.bcd.DeviceType.Vhd)));
    try testing.expectEqual(@as(u32, 0x20000004), @as(u32, @intFromEnum(hivex.bcd.DeviceType.Ramdisk)));
    try testing.expectEqual(@as(u32, 0x30000001), @as(u32, @intFromEnum(hivex.bcd.DeviceType.File)));
}

test "BcdElement init" {
    const elem = hivex.bcd.BcdElement.init(0x12000001);
    try testing.expectEqual(@as(hivex.bcd.ElementType, 0x12000001), elem.getType());
    try testing.expect(elem.validate());
}

test "BcdElement getValueType" {
    const device_elem = hivex.bcd.BcdElement.init(0x11000001);
    const integer_elem = hivex.bcd.BcdElement.init(0x12000001);
    const boolean_elem = hivex.bcd.BcdElement.init(0x13000001);
    const string_elem = hivex.bcd.BcdElement.init(0x15000001);

    try testing.expectEqual(hivex.bcd.BcdElement.ElementValueType.Device, device_elem.getValueType());
    try testing.expectEqual(hivex.bcd.BcdElement.ElementValueType.Integer, integer_elem.getValueType());
    try testing.expectEqual(hivex.bcd.BcdElement.ElementValueType.Boolean, boolean_elem.getValueType());
    try testing.expectEqual(hivex.bcd.BcdElement.ElementValueType.String, string_elem.getValueType());
}

test "RamdiskOptions" {
    const opts = hivex.bcd.RamdiskOptions{
        .image_offset_bytes = 0x1000,
        .image_raw_bytes = 0x100000,
    };

    try testing.expectEqual(@as(u64, 0x1000), opts.image_offset_bytes);
    try testing.expectEqual(@as(u64, 0x100000), opts.image_raw_bytes);
}

test "ObjectListElement" {
    var elem = hivex.bcd.ObjectListElement.init(std.heap.page_allocator);
    defer elem.deinit();

    const guid1 = hivex.bcd.GUID.generate();
    const guid2 = hivex.bcd.GUID.generate();
    const guid3 = hivex.bcd.GUID.generate();

    try elem.add(guid1);
    try elem.add(guid2);
    try elem.add(guid3);

    try testing.expectEqual(@as(usize, 3), elem.getObjects().len);

    elem.remove(&guid2);
    try testing.expectEqual(@as(usize, 2), elem.getObjects().len);

    const objects = elem.getObjects();
    try testing.expect(objects[0].eql(&guid1));
    try testing.expect(objects[1].eql(&guid3));
}

test "IntegerListElement" {
    var elem = hivex.bcd.IntegerListElement.init(std.heap.page_allocator);
    defer elem.deinit();

    try elem.add(100);
    try elem.add(200);
    try elem.add(300);

    try testing.expectEqual(@as(usize, 3), elem.getValues().len);

    const values = elem.getValues();
    try testing.expectEqual(@as(u64, 100), values[0]);
    try testing.expectEqual(@as(u64, 200), values[1]);
    try testing.expectEqual(@as(u64, 300), values[2]);
}
