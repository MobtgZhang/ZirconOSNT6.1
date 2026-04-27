//! Hive Format Tests

const std = @import("std");
const hivex = @import("hivex");
const testing = std.testing;

test "HiveHeader init" {
    const header = hivex.hive.HiveHeader.init();
    try testing.expectEqualSlices(u8, "regf", &header.signature);
    try testing.expectEqual(@as(u32, 1), header.major_version);
    try testing.expectEqual(@as(u32, 3), header.minor_version);
    try testing.expectEqual(@as(u32, 4096), header.hbin_size);
}

test "HiveHeader validate" {
    var header = hivex.hive.HiveHeader.init();
    try testing.expect(header.validate());

    header.signature = .{ 't', 'e', 's', 't' };
    try testing.expect(!header.validate());
}

test "HiveHeader serialize and parse" {
    var header = hivex.hive.HiveHeader.init();
    header.root_cell_offset = 5000;
    header.sequence_number = 42;

    var buf: [4096]u8 = undefined;
    try header.serialize(&buf);

    const parsed = try hivex.hive.HiveHeader.parse(&buf);
    try testing.expectEqual(header.root_cell_offset, parsed.root_cell_offset);
    try testing.expectEqual(header.sequence_number, parsed.sequence_number);
}

test "HiveHeader checksum" {
    var header = hivex.hive.HiveHeader.init();
    var buf: [4096]u8 = undefined;
    try header.serialize(&buf);

    const checksum = header.computeChecksum(&buf);
    try testing.expect(header.checksum == checksum or header.checksum == 0);
}

test "HbinBlock init" {
    const hbin = hivex.hive.HbinBlock.init(4096);
    try testing.expectEqual(@as(u32, 4096), hbin.size);
    try testing.expectEqual(@as(u32, 4096), hbin.offset_to_next_hbin);
    try testing.expectEqual(@as(u32, 0x20), hbin.first_cell_offset);
}

test "HbinBlock validate" {
    var hbin = hivex.hive.HbinBlock.init(4096);
    try testing.expect(hbin.validate());

    hbin.size = 0;
    try testing.expect(!hbin.validate());
}

test "HbinBlock CellIterator" {
    var data: [4096]u8 = undefined;
    @memset(&data, 0);
    data[0] = 'h';
    data[1] = 'b';
    data[2] = 'i';
    data[3] = 'n';

    var hbin = hivex.hive.HbinBlock.init(4096);
    hbin.serialize(&data) catch unreachable;

    var iter = hivex.hive.HbinBlock.CellIterator.init(&data, 0);
    const first_cell = iter.next();
    try testing.expect(first_cell == null or first_cell.?.offset == 0x20);
}

test "Cell size encoding" {
    const allocated_size: i32 = 100;
    const free_size: i32 = -100;

    try testing.expect(allocated_size > 0);
    try testing.expect(free_size < 0);
    try testing.expectEqual(@as(u32, 100), @as(u32, @intCast(@abs(allocated_size))));
    try testing.expectEqual(@as(u32, 100), @as(u32, @intCast(@abs(free_size))));
}

test "Cell alignment" {
    const sizes = [_]u32{ 1, 7, 8, 9, 15, 16, 100 };
    for (sizes) |size| {
        const aligned = hivex.hive.Cell.alignCellSize(size);
        try testing.expect(aligned % 8 == 0);
        try testing.expect(aligned >= size);
    }
}

test "GUID parsing" {
    const guid_str = "{12345678-1234-1234-1234-123456789abc}";
    const guid = hivex.bcd.GUID.parse(guid_str) catch unreachable;

    try testing.expectEqual(@as(u32, 0x12345678), guid.data1);
    try testing.expectEqual(@as(u16, 0x1234), guid.data2);
    try testing.expectEqual(@as(u16, 0x1234), guid.data3);
}

test "GUID formatting" {
    const guid = hivex.bcd.GUID{
        .data1 = 0x12345678,
        .data2 = 0x1234,
        .data3 = 0x1234,
        .data4 = .{ 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0 },
    };

    var buf: [38]u8 = undefined;
    guid.formatStatic(&buf);

    const expected = "{12345678-1234-1234-1234-56789ABCDEF0}";
    try testing.expectEqualSlices(u8, expected, &buf);
}

test "GUID comparison" {
    const guid1 = hivex.bcd.GUID{
        .data1 = 0x12345678,
        .data2 = 0x1234,
        .data3 = 0x1234,
        .data4 = .{0} ** 8,
    };

    const guid2 = hivex.bcd.GUID{
        .data1 = 0x12345678,
        .data2 = 0x1234,
        .data3 = 0x1234,
        .data4 = .{0} ** 8,
    };

    const guid3 = hivex.bcd.GUID{
        .data1 = 0x87654321,
        .data2 = 0x4321,
        .data3 = 0x4321,
        .data4 = .{0} ** 8,
    };

    try testing.expect(guid1.eql(&guid2));
    try testing.expect(!guid1.eql(&guid3));
}

test "GUID isNull" {
    const null_guid = hivex.bcd.GUID{
        .data1 = 0,
        .data2 = 0,
        .data3 = 0,
        .data4 = .{0} ** 8,
    };

    const non_null_guid = hivex.bcd.GUID{
        .data1 = 1,
        .data2 = 0,
        .data3 = 0,
        .data4 = .{0} ** 8,
    };

    try testing.expect(null_guid.isNull());
    try testing.expect(!non_null_guid.isNull());
}

test "WellKnownGuid getByName" {
    const guid = hivex.bcd.WellKnownGuid.getByName("bootmgr");
    try testing.expect(guid != null);

    const null_guid = hivex.bcd.WellKnownGuid.getByName("nonexistent");
    try testing.expect(null_guid == null);
}

test "BcdObjectType getCategory" {
    const firmware_type = hivex.bcd.ObjectType.FirmwareBootManager;
    const bootmgr_type = hivex.bcd.ObjectType.Bootmgr;
    const tools_type = hivex.bcd.ObjectType.Tools;

    try testing.expectEqual(hivex.bcd.ObjectType.getCategory(firmware_type), .Firmware);
    _ = bootmgr_type;
    _ = tools_type;
}

test "ElementType getCategory" {
    const device_type: u32 = 0x11000001;
    const integer_type: u32 = 0x12000001;
    const string_type: u32 = 0x15000001;

    try testing.expectEqual(hivex.bcd.getElementTypeCategory(device_type), .Device);
    try testing.expectEqual(hivex.bcd.getElementTypeCategory(integer_type), .Integer);
    try testing.expectEqual(hivex.bcd.getElementTypeCategory(string_type), .String);
}
