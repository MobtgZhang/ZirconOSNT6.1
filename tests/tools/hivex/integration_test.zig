//! Integration Tests for hivex tools

const std = @import("std");
const hivex = @import("../../../src/tools/hivex/root.zig");
const testing = std.testing;

test "Version info" {
    const version = hivex.getVersion();
    try testing.expectEqual(@as(u32, 1), version.major);
    try testing.expectEqual(@as(u32, 0), version.minor);
    try testing.expectEqual(@as(u32, 0), version.patch);
}

test "Version string" {
    const version_str = hivex.getVersionString();
    try testing.expectEqualSlices(u8, "1.0.0", version_str);
}

test "Library init/deinit" {
    hivex.init();
    hivex.deinit();
}

test "Error types exist" {
    const hive_errors = [_]hivex.Error{
        error.InvalidHeader,
        error.InvalidSignature,
        error.BufferTooSmall,
        error.FileNotFound,
        error.IoError,
        error.OutOfMemory,
    };

    for (hive_errors) |err| {
        _ = err;
    }
}

test "Registry error types" {
    const registry_errors = [_]hivex.Error{
        error.KeyNotFound,
        error.ValueNotFound,
        error.AccessDenied,
        error.InvalidPath,
    };

    for (registry_errors) |err| {
        _ = err;
    }
}

test "BCD error types" {
    const bcd_errors = [_]hivex.Error{
        error.ObjectNotFound,
        error.InvalidStore,
        error.InvalidTemplate,
    };

    for (bcd_errors) |err| {
        _ = err;
    }
}

test "Full BcdObject lifecycle" {
    const guid = hivex.bcd.GUID.generate();
    var obj = hivex.bcd.BcdObject.init(guid, hivex.bcd.ObjectType.OsLoader);
    defer obj.deinit();

    try testing.expect(obj.validate());

    const elem1 = hivex.bcd.BcdElement.init(hivex.bcd.ElementType.Common.TIMEOUT);
    const elem2 = hivex.bcd.BcdElement.init(hivex.bcd.ElementType.Common.OS_DEVICE);

    try obj.setElement(elem1);
    try obj.setElement(elem2);

    try testing.expectEqual(@as(usize, 2), obj.getElementCount());
    try testing.expect(obj.hasElement(hivex.bcd.ElementType.Common.TIMEOUT));
    try testing.expect(obj.hasElement(hivex.bcd.ElementType.Common.OS_DEVICE));

    obj.deleteElement(hivex.bcd.ElementType.Common.OS_DEVICE);
    try testing.expectEqual(@as(usize, 1), obj.getElementCount());

    const retrieved = obj.getElement(hivex.bcd.ElementType.Common.TIMEOUT);
    try testing.expect(retrieved != null);
}

test "Well-known GUIDs complete list" {
    const names = [_][]const u8{
        "bootmgr",
        "bootloaders",
        "default",
        "current",
        "memdiag",
        "resume",
        "resumefilter",
        "setup",
        "recovery",
        "diag",
        "failed",
        "dbgsettings",
        "hypervisor",
        "realmode",
        "bad",
    };

    for (names) |name| {
        const guid = hivex.bcd.WellKnownGuid.getByName(name);
        try testing.expect(guid != null);

        const guid_name = hivex.bcd.WellKnownGuid.getNameByGuid(guid.?);
        try testing.expect(guid_name != null);
        try testing.expectEqualSlices(u8, name, guid_name.?);

        const desc = hivex.bcd.WellKnownGuid.getDescriptionByGuid(guid.?);
        try testing.expect(desc != null);
    }
}

test "DeviceElement full path" {
    var device = hivex.bcd.DeviceElement.init();
    device.setPartition("\\Device\\Harddisk0\\Partition1", "\\EFI\\Microsoft\\Boot\\bootmgfw.efi");
    try testing.expectEqual(hivex.bcd.DeviceType.Partition, device.device_type);

    var vhd_device = hivex.bcd.DeviceElement.init();
    vhd_device.setVhd("C:\\VHDs\\boot.vhdx", 0x12345678, "\\Windows\\system32\\winload.efi");
    try testing.expectEqual(hivex.bcd.DeviceType.Vhd, vhd_device.device_type);
}

test "Template structures" {
    const boot_opts = hivex.bcd.ZirconOsTemplate.BootOptions{
        .timeout = 30,
        .boot_menu = true,
        .boot_logo = true,
        .default_entry = null,
    };
    try testing.expectEqual(@as(u32, 30), boot_opts.timeout);
    try testing.expect(boot_opts.boot_menu);
    try testing.expect(boot_opts.boot_logo);

    const debug_opts = hivex.bcd.ZirconOsTemplate.DebugConfig{
        .enabled = true,
        .port = 0x3F8,
        .baudrate = 115200,
        .com_port = 1,
    };
    try testing.expect(debug_opts.enabled);
    try testing.expectEqual(@as(u32, 115200), debug_opts.baudrate);

    const recovery_opts = hivex.bcd.RecoveryTemplate.RecoveryOptions{
        .enable_diagnostics = true,
        .enable_startup_repair = true,
        .enable_system_restore = true,
        .recovery_image_path = null,
    };
    try testing.expect(recovery_opts.enable_diagnostics);
    try testing.expect(recovery_opts.enable_startup_repair);
}
