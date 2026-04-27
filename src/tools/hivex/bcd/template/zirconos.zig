//! ZirconOS BCD Template
//! 
//! Creates ZirconOS-specific boot configuration.

const std = @import("std");
const object = @import("../object/root.zig");
const element = @import("../element/root.zig");
const Self = @This();

/// ZirconOS BCD Template
pub const ZirconOsTemplate = struct {
    /// Create default ZirconOS BCD
    pub fn createDefault(allocator: std.mem.Allocator) !std.ArrayList(object.Object) {
        var objects = try std.ArrayList(object.Object).initCapacity(allocator, 16);

        var bootmgr = object.Object.init(object.GUID.generate(), object.ObjectType.Bootmgr);
        bootmgr.description = try allocator.dupe(u8, "ZirconOS Boot Manager");
        try objects.append(allocator, bootmgr);

        var loader = object.Object.init(object.GUID.generate(), object.ObjectType.OsLoader);
        loader.description = try allocator.dupe(u8, "ZirconOS");
        try objects.append(allocator, loader);

        return objects;
    }

    /// Create boot entry BCD
    pub fn createForBoot(allocator: std.mem.Allocator, kernel_path: []const u8, initrd_path: []const u8) !object.Object {
        var obj = object.Object.init(object.GUID.generate(), object.ObjectType.OsLoader);
        obj.description = try allocator.dupe(u8, "ZirconOS Boot");

        _ = kernel_path;
        _ = initrd_path;

        return obj;
    }

    /// Create recovery entry BCD
    pub fn createForRecovery(allocator: std.mem.Allocator) !object.Object {
        var obj = object.Object.init(object.GUID.generate(), object.ObjectType.RecoveryOs);
        obj.description = try allocator.dupe(u8, "ZirconOS Recovery");

        return obj;
    }

    /// Add Zircon loader to store
    pub fn addZirconLoader(allocator: std.mem.Allocator, store: *std.ArrayList(object.Object), loader_path: []const u8) !void {
        var obj = object.Object.init(object.GUID.generate(), object.ObjectType.OsLoader);
        obj.description = try allocator.dupe(u8, "ZirconOS Loader");
        _ = loader_path;
        try store.append(allocator, obj);
    }

    /// Add kernel to store
    pub fn addKernel(allocator: std.mem.Allocator, store: *std.ArrayList(object.Object), kernel_path: []const u8) !void {
        var obj = object.Object.init(object.GUID.generate(), object.ObjectType.OsLoader);
        obj.description = try allocator.dupe(u8, "ZirconOS Kernel");
        _ = kernel_path;
        try store.append(allocator, obj);
    }

    /// Add initrd to store
    pub fn addInitrd(allocator: std.mem.Allocator, store: *std.ArrayList(object.Object), initrd_path: []const u8) !void {
        var obj = object.Object.init(object.GUID.generate(), object.ObjectType.OsLoader);
        obj.description = try allocator.dupe(u8, "ZirconOS Initrd");
        _ = initrd_path;
        try store.append(allocator, obj);
    }

    /// Set boot options
    pub fn setBootOptions(allocator: std.mem.Allocator, store: *std.ArrayList(object.Object), options: BootOptions) !void {
        _ = allocator;
        _ = store;
        _ = options;
    }

    /// Configure GOP (Graphics Output Protocol)
    pub fn configureGop(allocator: std.mem.Allocator, store: *std.ArrayList(object.Object), gop_config: GopConfig) !void {
        _ = allocator;
        _ = store;
        _ = gop_config;
    }

    /// Configure debug settings
    pub fn configureDebug(allocator: std.mem.Allocator, store: *std.ArrayList(object.Object), debug_config: DebugConfig) !void {
        _ = allocator;
        _ = store;
        _ = debug_config;
    }

    /// Add boot entry
    pub fn addBootEntry(allocator: std.mem.Allocator, store: *std.ArrayList(object.Object), entry: BootEntry) !void {
        var obj = object.Object.init(object.GUID.generate(), object.ObjectType.OsLoader);
        obj.description = try allocator.dupe(u8, entry.name);
        try store.append(allocator, obj);
    }
};

/// Boot options
pub const BootOptions = struct {
    /// Boot timeout in seconds
    timeout: u32 = 30,
    /// Boot device path
    boot_device: []const u8 = "",
    /// Kernel command line
    kernel_args: []const u8 = "",
    /// Enable serial debug
    serial_debug: bool = false,
    /// Serial port
    serial_port: u32 = 0x3F8,
};

/// GOP configuration
pub const GopConfig = struct {
    /// GOP driver path
    driver_path: []const u8 = "",
    /// Resolution width
    width: u32 = 1920,
    /// Resolution height
    height: u32 = 1080,
};

/// Debug configuration
pub const DebugConfig = struct {
    /// Enable debug
    enabled: bool = false,
    /// Debug port
    port: u32 = 0x3F8,
    /// Baud rate
    baudrate: u32 = 115200,
};

/// Boot entry
pub const BootEntry = struct {
    /// Entry name
    name: []const u8,
    /// Kernel path
    kernel_path: []const u8,
    /// Initrd path
    initrd_path: []const u8,
    /// Command line
    cmdline: []const u8 = "",
};
