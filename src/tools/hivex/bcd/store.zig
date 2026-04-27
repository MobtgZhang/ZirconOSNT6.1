//! BCD Store Module
//! 
//! BCD Store management.

const std = @import("std");
const hive = @import("../hive/root.zig");
const object = @import("object/root.zig");
const reader = @import("parser/reader.zig");
const writer = @import("parser/writer.zig");
const template = @import("template/root.zig");
const Self = @This();

/// BCD Store
pub const BcdStore = struct {
    /// Underlying hive
    hive: hive.Hive,

    /// Objects in the store
    objects: std.ArrayList(object.Object),

    /// Template type
    template_type: ?TemplateType,

    /// Create a new BCD store
    pub fn init(allocator: std.mem.Allocator) BcdStore {
        _ = allocator;
        return BcdStore{
            .hive = undefined,
            .objects = .{ .items = &.{}, .capacity = 0 },
            .template_type = null,
        };
    }

    /// Open an existing BCD store
    pub fn open(path: []const u8) !BcdStore {
        const hive_store = try hive.Hive.open(path, true);
        
        var store = BcdStore{
            .hive = hive_store,
            .objects = try std.ArrayList(object.Object).initCapacity(std.heap.page_allocator, 128),
            .template_type = null,
        };

        var bcd_reader = try reader.Reader.init(store.hive.getData(), store.hive.getRootOffset());
        try bcd_reader.readObjectList();
        
        // Transfer objects from reader to store
        for (bcd_reader.objects.items) |obj| {
            try store.objects.append(std.heap.page_allocator, obj);
        }

        return store;
    }

    /// Create a new BCD store
    pub fn create(path: []const u8, template_type: ?TemplateType) !BcdStore {
        var store = BcdStore{
            .hive = undefined,
            .objects = try std.ArrayList(object.Object).initCapacity(std.heap.page_allocator, 128),
            .template_type = template_type,
        };

        if (template_type) |tt| {
            switch (tt) {
                .Windows => {
                    const objs = try template.windows.WindowsTemplate.createDefault(std.heap.page_allocator);
                    for (objs.items) |obj| {
                        try store.objects.append(std.heap.page_allocator, obj);
                    }
                },
                .Recovery => {
                    const objs = try template.recovery.RecoveryTemplate.create(std.heap.page_allocator);
                    for (objs.items) |obj| {
                        try store.objects.append(std.heap.page_allocator, obj);
                    }
                },
                .ZirconOs => {
                    const objs = try template.zirconos.ZirconOsTemplate.createDefault(std.heap.page_allocator);
                    for (objs.items) |obj| {
                        try store.objects.append(std.heap.page_allocator, obj);
                    }
                },
            }
        }

        _ = path;

        return store;
    }

    /// Save the BCD store
    pub fn save(self: *BcdStore) !void {
        try self.hive.flush();
    }

    /// Close the BCD store
    pub fn close(self: *BcdStore) void {
        for (self.objects.items) |*obj| {
            obj.deinit();
        }
        self.objects.deinit(std.heap.page_allocator);
        self.hive.close();
    }

    /// Get an object by GUID
    pub fn getObject(self: *const BcdStore, guid: *const object.GUID) ?*object.Object {
        for (self.objects.items) |*obj| {
            if (obj.id.eql(guid)) {
                return obj;
            }
        }
        return null;
    }

    /// Create a new object
    pub fn createObject(self: *BcdStore, object_type: object.ObjectType, guid: ?object.GUID) !*object.Object {
        const new_guid = guid orelse object.GUID.generate();
        const obj = object.Object.init(new_guid, object_type);
        try self.objects.append(std.heap.page_allocator, obj);
        return &self.objects.items[self.objects.items.len - 1];
    }

    /// Delete an object
    pub fn deleteObject(self: *BcdStore, guid: *const object.GUID) !void {
        for (self.objects.items, 0..) |*obj, i| {
            if (obj.id.eql(guid)) {
                obj.deinit();
                _ = self.objects.swapRemove(i);
                return;
            }
        }
        return error.ObjectNotFound;
    }

    /// Enumerate all objects
    pub fn enumerateObjects(self: *const BcdStore) []*object.Object {
        return self.objects.items;
    }

    /// Find objects by type
    pub fn findByType(self: *const BcdStore, object_type: object.ObjectType) std.ArrayList(*object.Object) {
        var result = std.ArrayList(*object.Object).init(std.heap.page_allocator);
        for (self.objects.items) |*obj| {
            if (obj.object_type == object_type) {
                result.append(std.heap.page_allocator, obj) catch continue;
            }
        }
        return result;
    }

    /// Get a well-known object
    pub fn getWellKnownObject(self: *const BcdStore, name: []const u8) ?*object.Object {
        const guid = object.WellKnownGuid.getByName(name) orelse return null;
        return self.getObject(&guid);
    }

    /// Backup the store
    pub fn backup(self: *const BcdStore, backup_path: []const u8) !void {
        _ = self;
        _ = backup_path;
    }

    /// Restore from backup
    pub fn restore(self: *BcdStore, backup_path: []const u8) !void {
        _ = self;
        _ = backup_path;
    }
};

/// Template type
pub const TemplateType = enum {
    /// Windows template
    Windows,
    /// Recovery template
    Recovery,
    /// ZirconOS template
    ZirconOs,
};

/// Error types
pub const Error = error{
    ObjectNotFound,
    InvalidStore,
    IoError,
    InvalidTemplate,
};
