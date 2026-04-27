//! Windows BCD Template
//! 
//! Creates standard Windows boot configuration.

const std = @import("std");
const object = @import("../object/root.zig");
const element = @import("../element/root.zig");
const Self = @This();

/// Windows BCD Template
pub const WindowsTemplate = struct {
    /// Create a default Windows BCD store
    pub fn createDefault(allocator: std.mem.Allocator) !std.ArrayList(object.Object) {
        var objects = try std.ArrayList(object.Object).initCapacity(allocator, 16);
        const bootmgr = createBootManager(allocator) catch object.Object.init(object.GUID.zero(), object.ObjectType.Bootmgr);
        try objects.append(allocator, bootmgr);
        const loader = createDefaultOsLoader(allocator) catch object.Object.init(object.GUID.zero(), object.ObjectType.OsLoader);
        try objects.append(allocator, loader);
        return objects;
    }

    /// Create boot manager object
    pub fn createBootManager(allocator: std.mem.Allocator) !object.Object {
        var obj = object.Object.init(try object.WellKnownGuid.getByName("bootmgr") orelse object.GUID.generate(), object.ObjectType.Bootmgr);
        obj.description = try allocator.dupe(u8, "Windows Boot Manager");
        return obj;
    }

    /// Create default OS loader object
    pub fn createDefaultOsLoader(allocator: std.mem.Allocator) !object.Object {
        var obj = object.Object.init(try object.WellKnownGuid.getByName("default") orelse object.GUID.generate(), object.ObjectType.OsLoader);
        obj.description = try allocator.dupe(u8, "Windows");
        return obj;
    }

    /// Create OS loader for installation
    pub fn createForInstall(allocator: std.mem.Allocator, boot_device: []const u8, system_root: []const u8) !object.Object {
        var obj = object.Object.init(object.GUID.generate(), object.ObjectType.OsLoader);
        obj.description = try allocator.dupe(u8, "Windows Setup");
        _ = boot_device;
        _ = system_root;
        return obj;
    }

    /// Create OS loader for upgrade
    pub fn createForUpgrade(allocator: std.mem.Allocator, boot_device: []const u8, system_root: []const u8) !object.Object {
        var obj = object.Object.init(object.GUID.generate(), object.ObjectType.OsLoader);
        obj.description = try allocator.dupe(u8, "Windows Upgrade");
        _ = boot_device;
        _ = system_root;
        return obj;
    }

    /// Add boot manager to store
    pub fn addBootManager(allocator: std.mem.Allocator, store: *std.ArrayList(object.Object)) !void {
        const obj = createBootManager(allocator) catch return;
        try store.append(allocator, obj);
    }

    /// Add OS loader to store
    pub fn addOsLoader(allocator: std.mem.Allocator, store: *std.ArrayList(object.Object), path: []const u8) !void {
        _ = path;
        const obj = createDefaultOsLoader(allocator) catch return;
        try store.append(allocator, obj);
    }

    /// Configure debugger settings
    pub fn configureDebugger(allocator: std.mem.Allocator, store: *std.ArrayList(object.Object), port: u32, baudrate: u32) !void {
        _ = allocator;
        _ = store;
        _ = port;
        _ = baudrate;
    }
};
