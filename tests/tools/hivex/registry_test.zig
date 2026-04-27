//! Registry Tests

const std = @import("std");
const hivex = @import("../../../src/tools/hivex/root.zig");
const testing = std.testing;

test "Registry Value types" {
    const value_types = [_]hivex.registry.Value.ValueType{
        hivex.hive.VkCell.ValueType.NONE,
        hivex.hive.VkCell.ValueType.SZ,
        hivex.hive.VkCell.ValueType.EXPAND_SZ,
        hivex.hive.VkCell.ValueType.BINARY,
        hivex.hive.VkCell.ValueType.DWORD,
        hivex.hive.VkCell.ValueType.QWORD,
        hivex.hive.VkCell.ValueType.MULTI_SZ,
    };

    for (value_types) |vt| {
        const name = hivex.hive.VkCell.ValueType.getName(vt);
        try testing.expect(name.len > 0);
    }
}

test "Value type names" {
    try testing.expectEqualSlices(u8, "REG_SZ", hivex.hive.VkCell.ValueType.SZ.getName());
    try testing.expectEqualSlices(u8, "REG_DWORD", hivex.hive.VkCell.ValueType.DWORD.getName());
    try testing.expectEqualSlices(u8, "REG_BINARY", hivex.hive.VkCell.ValueType.BINARY.getName());
    try testing.expectEqualSlices(u8, "REG_MULTI_SZ", hivex.hive.VkCell.ValueType.MULTI_SZ.getName());
}

test "Value createStringValue" {
    const value = hivex.registry.Value.createStringValue("TestValue", "Hello World");
    try testing.expectEqual(hivex.hive.VkCell.ValueType.SZ, value.value_type);
}

test "Value createDwordValue" {
    const value = hivex.registry.Value.createDwordValue("TestDword", 0x12345678);
    try testing.expectEqual(hivex.hive.VkCell.ValueType.DWORD, value.value_type);
}

test "Value createBinaryValue" {
    const data = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    const value = hivex.registry.Value.createBinaryValue("TestBinary", &data);
    try testing.expectEqual(hivex.hive.VkCell.ValueType.BINARY, value.value_type);
}

test "BcdObject init" {
    const guid = hivex.bcd.GUID.generate();
    const obj_type = hivex.bcd.ObjectType.OsLoader;
    const obj = hivex.bcd.BcdObject.init(guid, obj_type);

    try testing.expect(obj.id.eql(&guid));
    try testing.expectEqual(obj_type, obj.object_type);
    try testing.expectEqual(@as(usize, 0), obj.getElementCount());
}

test "BcdObject getElement/setElement" {
    const guid = hivex.bcd.GUID.generate();
    const obj = hivex.bcd.BcdObject.init(guid, hivex.bcd.ObjectType.OsLoader);

    const elem_type: hivex.bcd.ElementType = 0x12000001;
    const elem = hivex.bcd.BcdElement.init(elem_type);
    defer {
        elem.deinit();
        std.heap.page_allocator.free(elem);
    }

    try obj.setElement(elem);
    try testing.expectEqual(@as(usize, 1), obj.getElementCount());
    try testing.expect(obj.hasElement(elem_type));

    const retrieved = obj.getElement(elem_type);
    try testing.expect(retrieved != null);
}

test "BcdObject deleteElement" {
    const guid = hivex.bcd.GUID.generate();
    const obj = hivex.bcd.BcdObject.init(guid, hivex.bcd.ObjectType.OsLoader);

    const elem_type: hivex.bcd.ElementType = 0x12000001;
    const elem = hivex.bcd.BcdElement.init(elem_type);
    defer {
        elem.deinit();
        std.heap.page_allocator.free(elem);
    }

    try obj.setElement(elem);
    try testing.expectEqual(@as(usize, 1), obj.getElementCount());

    obj.deleteElement(elem_type);
    try testing.expectEqual(@as(usize, 0), obj.getElementCount());
    try testing.expect(!obj.hasElement(elem_type));
}

test "BcdObject validate" {
    const guid = hivex.bcd.GUID.generate();
    const obj = hivex.bcd.BcdObject.init(guid, hivex.bcd.ObjectType.OsLoader);
    try testing.expect(obj.validate());
}

test "BcdObject isWellKnown" {
    const well_known_guid = hivex.bcd.WellKnownGuid.getByName("bootmgr") orelse return error.TestFailed;
    const obj = hivex.bcd.BcdObject.init(well_known_guid, hivex.bcd.ObjectType.Bootmgr);
    try testing.expect(obj.isWellKnown());

    const random_guid = hivex.bcd.GUID.generate();
    const obj2 = hivex.bcd.BcdObject.init(random_guid, hivex.bcd.ObjectType.OsLoader);
    try testing.expect(!obj2.isWellKnown());
}

test "DeviceElement creation" {
    var device = hivex.bcd.DeviceElement.init();
    try testing.expectEqual(hivex.bcd.DeviceType.None, device.device_type);

    device.setPartition("\\Device\\Harddisk0\\Partition1", "\\Windows\\System32\\boot.exe");
    try testing.expectEqual(hivex.bcd.DeviceType.Partition, device.device_type);
}

test "StringElement creation" {
    const elem = hivex.bcd.StringElement.init("Test String");
    try testing.expectEqualSlices(u8, "Test String", elem.getValue());
}

test "IntegerElement creation" {
    const elem = hivex.bcd.IntegerElement.init(42);
    try testing.expectEqual(@as(u64, 42), elem.getValue());
}

test "BooleanElement creation" {
    const elem_true = hivex.bcd.BooleanElement.init(true);
    const elem_false = hivex.bcd.BooleanElement.init(false);

    try testing.expect(elem_true.getValue());
    try testing.expect(!elem_false.getValue());
}

test "TextWriter format types" {
    var writer = hivex.bcd.BcdTextWriter.init(std.heap.page_allocator, .Bcdedit);
    defer writer.deinit();

    try testing.expectEqual(@as(usize, 0), writer.getOutput().len);
}

test "TextWriter format Guid" {
    var writer = hivex.bcd.BcdTextWriter.init(std.heap.page_allocator, .Bcdedit);
    defer writer.deinit();

    const guid = hivex.bcd.GUID{
        .data1 = 0x12345678,
        .data2 = 0x1234,
        .data3 = 0x1234,
        .data4 = .{0} ** 8,
    };

    const guid_str = try writer.formatGuid(&guid, std.heap.page_allocator);
    defer std.heap.page_allocator.free(guid_str);

    try testing.expect(guid_str.len > 0);
    try testing.expect(std.mem.indexOf(u8, guid_str, "{") != null);
}
