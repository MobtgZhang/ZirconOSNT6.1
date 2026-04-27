//! BCD Tests

const std = @import("std");
const hivex = @import("../../../src/tools/hivex/root.zig");
const testing = std.testing;

test "BcdStore init" {
    const store = hivex.bcd.BcdStore.init(std.heap.page_allocator);
    try testing.expectEqual(@as(usize, 0), store.objects.items.len);
    try testing.expect(store.template_type == null);
}

test "WindowsTemplate createDefault" {
    const objects = hivex.bcd.WindowsTemplate.createDefault(std.heap.page_allocator) catch {
        return error.TemplateCreateFailed;
    };
    defer {
        for (objects.items) |*obj| obj.deinit();
        objects.deinit();
    }

    try testing.expect(objects.items.len > 0);
}

test "RecoveryTemplate create" {
    const objects = hivex.RecoveryTemplate.create(std.heap.page_allocator) catch {
        return error.TemplateCreateFailed;
    };
    defer {
        for (objects.items) |*obj| obj.deinit();
        objects.deinit();
    }

    try testing.expect(objects.items.len > 0);
}

test "ZirconOsTemplate createDefault" {
    const objects = hivex.ZirconOsTemplate.createDefault(std.heap.page_allocator) catch {
        return error.TemplateCreateFailed;
    };
    defer {
        for (objects.items) |*obj| obj.deinit();
        objects.deinit();
    }

    try testing.expect(objects.items.len > 0);
}

test "ZirconOsTemplate BootEntry" {
    const entry = hivex.ZirconOsTemplate.BootEntry{
        .name = "Test Boot",
        .kernel_path = "\\EFI\\ZirconOS\\vmlinuz",
        .initrd_path = "\\EFI\\ZirconOS\\initrd.img",
        .cmdline = "quiet",
        .options = hivex.ZirconOsTemplate.BootOptions{
            .timeout = 10,
            .boot_menu = true,
            .boot_logo = false,
            .default_entry = null,
        },
    };

    try testing.expectEqualSlices(u8, "Test Boot", entry.name);
    try testing.expectEqual(@as(u32, 10), entry.options.timeout);
}

test "GopConfig defaults" {
    const gop = hivex.ZirconOsTemplate.GopConfig{
        .driver_path = null,
        .width = 1920,
        .height = 1080,
        .refresh_rate = 60,
    };

    try testing.expectEqual(@as(u32, 1920), gop.width);
    try testing.expectEqual(@as(u32, 1080), gop.height);
    try testing.expectEqual(@as(u32, 60), gop.refresh_rate);
}

test "DebugConfig defaults" {
    const debug = hivex.ZirconOsTemplate.DebugConfig{
        .enabled = false,
        .port = 0x3F8,
        .baudrate = 115200,
        .com_port = 1,
    };

    try testing.expect(!debug.enabled);
    try testing.expectEqual(@as(u32, 115200), debug.baudrate);
}

test "TemplateType enum" {
    try testing.expectEqual(@as(u32, 0), @as(u32, @intFromEnum(hivex.bcd.Store.TemplateType.Windows)));
    try testing.expectEqual(@as(u32, 1), @as(u32, @intFromEnum(hivex.bcd.Store.TemplateType.Recovery)));
    try testing.expectEqual(@as(u32, 2), @as(u32, @intFromEnum(hivex.bcd.Store.TemplateType.ZirconOs)));
}
