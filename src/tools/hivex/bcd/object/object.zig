//! BCD Object Module
//! 
//! Defines BCD objects and their operations.

const std = @import("std");
const type_module = @import("type.zig");
const guid_module = @import("guid.zig");

pub const ObjectType = type_module.ObjectType;
pub const GUID = guid_module.GUID;
pub const WellKnownGuid = guid_module.WellKnownGuid;

/// BCD Object
pub const Object = struct {
    /// Object GUID
    id: GUID,

    /// Object type
    object_type: ObjectType,

    /// Description
    description: []u8,

    /// Device element (optional)
    device: ?*Element,

    /// Elements
    elements: std.ArrayList(*Element),

    /// Create a new BCD object
    pub fn init(id: GUID, object_type: ObjectType) Object {
        return Object{
            .id = id,
            .object_type = object_type,
            .description = &.{},
            .device = null,
            .elements = .{ .items = &.{}, .capacity = 0 },
        };
    }

    /// Create a new BCD object with a name
    pub fn initWithName(id: GUID, object_type: ObjectType, name: []const u8) Object {
        return Object{
            .id = id,
            .object_type = object_type,
            .description = @constCast(name),
            .device = null,
            .elements = .{ .items = &.{}, .capacity = 0 },
        };
    }

    /// Get element by type
    pub fn getElement(self: *const Object, element_type: ElementType) ?*Element {
        for (self.elements.items) |elem| {
            if (elem.element_type == element_type) {
                return elem;
            }
        }
        return null;
    }

    /// Set an element
    pub fn setElement(self: *Object, elem: *Element) !void {
        for (self.elements.items, 0..) |e, i| {
            if (e.element_type == elem.element_type) {
                self.elements.items[i] = elem;
                return;
            }
        }
        try self.elements.append(elem);
    }

    /// Delete an element by type
    pub fn deleteElement(self: *Object, element_type: ElementType) void {
        var i: usize = 0;
        while (i < self.elements.items.len) {
            if (self.elements.items[i].element_type == element_type) {
                _ = self.elements.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Enumerate all elements
    pub fn enumerateElements(self: *const Object) []*Element {
        return self.elements.items;
    }

    /// Get element count
    pub fn getElementCount(self: *const Object) usize {
        return self.elements.items.len;
    }

    /// Check if object has an element
    pub fn hasElement(self: *const Object, element_type: ElementType) bool {
        return self.getElement(element_type) != null;
    }

    /// Get object type
    pub fn getType(self: *const Object) ObjectType {
        return self.object_type;
    }

    /// Set object type
    pub fn setType(self: *Object, object_type: ObjectType) void {
        self.object_type = object_type;
    }

    /// Validate the object
    pub fn validate(self: *const Object) bool {
        if (self.id.isNull()) return false;
        if (!self.object_type.isValid()) return false;
        return true;
    }

    /// Check if this is a well-known GUID
    pub fn isWellKnown(self: *const Object) bool {
        return WellKnownGuid.isWellKnown(&self.id);
    }

    /// Get well-known name
    pub fn getWellKnownName(self: *const Object) ?[]const u8 {
        return WellKnownGuid.getNameByGuid(&self.id);
    }

    /// Deinitialize
    pub fn deinit(self: *Object) void {
        for (self.elements.items) |elem| {
            elem.deinit();
        }
        self.elements.deinit(std.heap.page_allocator);
    }
};

/// BCD Element base type
pub const ElementType = u32;

/// Element value types
pub const ElementValueType = enum(u32) {
    /// Device element
    Device = 0x11000001,
    /// Object element
    Object = 0x19000001,
    /// Integer element
    Integer = 0x12000001,
    /// Boolean element
    Boolean = 0x13000001,
    /// String element
    String = 0x15000001,
    /// Object list element
    ObjectList = 0x17000001,
    /// Binary element
    Binary = 0x18000001,
    /// Integer list element
    IntegerList = 0x14000001,
};

/// BCD Element
pub const Element = struct {
    /// Element type
    element_type: ElementType,

    /// Device reference (for device elements)
    device: ?*DeviceElement,

    /// Element data
    data: []u8,

    /// Create a new element
    pub fn init(element_type: ElementType) *Element {
        const elem = std.heap.page_allocator.create(Element) catch unreachable;
        elem.* = Element{
            .element_type = element_type,
            .device = null,
            .data = &.{},
        };
        return elem;
    }

    /// Get element type
    pub fn getType(self: *const Element) ElementType {
        return self.element_type;
    }

    /// Get value type category
    pub fn getValueType(self: *const Element) ElementValueType {
        const category = (self.element_type >> 24) & 0xFF;
        return switch (category) {
            0x11, 0x12 => .Device,
            0x12 => .Integer,
            0x13 => .Boolean,
            0x15 => .String,
            0x17 => .ObjectList,
            0x18 => .Binary,
            0x19 => .Object,
            else => .Device,
        };
    }

    /// Serialize element data
    pub fn serialize(self: *const Element, allocator: std.mem.Allocator) ![]u8 {
        _ = allocator;
        return self.data;
    }

    /// Deserialize element data
    pub fn deserialize(self: *Element, data: []const u8) !void {
        self.data = @constCast(data);
    }

    /// Format element for display
    pub fn format(self: *const Element, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "Element 0x{x}", .{self.element_type});
    }

    /// Validate element
    pub fn validate(self: *const Element) bool {
        return self.element_type != 0;
    }

    /// Deinitialize
    pub fn deinit(self: *Element) void {
        if (self.device) |d| {
            d.deinit();
        }
    }
};

/// Device element
pub const DeviceElement = struct {
    /// Device type
    device_type: DeviceType,

    /// Partition path
    partition_path: ?[]u8,

    /// File path
    file_path: ?[]u8,

    /// VHD parent path
    vhd_parent: ?[]u8,

    /// VHD disk signature
    vhd_disk_signature: ?u32,

    /// RAM disk options
    ramdisk_options: ?RamdiskOptions,

    /// Create a new device element
    pub fn init() DeviceElement {
        return DeviceElement{
            .device_type = .None,
            .partition_path = null,
            .file_path = null,
            .vhd_parent = null,
            .vhd_disk_signature = null,
            .ramdisk_options = null,
        };
    }

    /// Set partition device
    pub fn setPartition(self: *DeviceElement, partition: []const u8, file: []const u8) void {
        self.device_type = .Partition;
        self.partition_path = @constCast(partition);
        self.file_path = @constCast(file);
    }

    /// Set file device
    pub fn setFile(self: *DeviceElement, file: []const u8) void {
        self.device_type = .File;
        self.file_path = @constCast(file);
    }

    /// Set VHD device
    pub fn setVhd(self: *DeviceElement, parent: []const u8, disk_sig: u32, file: []const u8) void {
        self.device_type = .Vhd;
        self.vhd_parent = @constCast(parent);
        self.vhd_disk_signature = disk_sig;
        self.file_path = @constCast(file);
    }

    /// Set RAM disk device
    pub fn setRamdisk(self: *DeviceElement, options: RamdiskOptions) void {
        self.device_type = .Ramdisk;
        self.ramdisk_options = options;
    }

    /// Deinitialize
    pub fn deinit(self: *DeviceElement) void {
        _ = self;
    }
};

/// Device type
pub const DeviceType = enum(u32) {
    /// No device
    None = 0x00000000,
    /// Boot device
    BootDevice = 0x10000001,
    /// Boot drive
    BootDrive = 0x10000002,
    /// System device
    SystemDevice = 0x10000003,
    /// System drive
    SystemDrive = 0x10000004,
    /// Partition
    Partition = 0x20000001,
    /// CD/DVD
    CdRom = 0x20000002,
    /// VHD
    Vhd = 0x20000003,
    /// RAM disk
    Ramdisk = 0x20000004,
    /// File
    File = 0x30000001,
    /// ADI
    Adi = 0x40000001,
};

/// RAM disk options
pub const RamdiskOptions = struct {
    /// Image offset in bytes
    image_offset_bytes: u64,

    /// Raw image bytes
    image_raw_bytes: u64,
};

/// String element
pub const StringElement = struct {
    /// String value
    value: []u8,

    /// Create a new string element
    pub fn init(value: []const u8) StringElement {
        return StringElement{
            .value = @constCast(value),
        };
    }

    /// Get value
    pub fn getValue(self: *const StringElement) []const u8 {
        return self.value;
    }
};

/// Integer element
pub const IntegerElement = struct {
    /// Integer value
    value: u64,

    /// Create a new integer element
    pub fn init(value: u64) IntegerElement {
        return IntegerElement{ .value = value };
    }

    /// Get value
    pub fn getValue(self: *const IntegerElement) u64 {
        return self.value;
    }
};

/// Boolean element
pub const BooleanElement = struct {
    /// Boolean value
    value: bool,

    /// Create a new boolean element
    pub fn init(value: bool) BooleanElement {
        return BooleanElement{ .value = value };
    }

    /// Get value
    pub fn getValue(self: *const BooleanElement) bool {
        return self.value;
    }
};

/// Object list element
pub const ObjectListElement = struct {
    /// Object GUIDs
    objects: std.ArrayList(GUID),

    /// Create a new object list element
    pub fn init(allocator: std.mem.Allocator) ObjectListElement {
        return ObjectListElement{
            .objects = std.ArrayList(GUID).init(allocator),
        };
    }

    /// Add an object
    pub fn add(self: *ObjectListElement, guid: GUID) !void {
        try self.objects.append(guid);
    }

    /// Remove an object
    pub fn remove(self: *ObjectListElement, guid: *const GUID) void {
        for (self.objects.items, 0..) |g, i| {
            if (g.eql(guid)) {
                _ = self.objects.swapRemove(i);
                return;
            }
        }
    }

    /// Get objects
    pub fn getObjects(self: *const ObjectListElement) []GUID {
        return self.objects.items;
    }

    /// Deinitialize
    pub fn deinit(self: *ObjectListElement) void {
        self.objects.deinit();
    }
};

/// Integer list element
pub const IntegerListElement = struct {
    /// Integer values
    values: std.ArrayList(u64),

    /// Create a new integer list element
    pub fn init(allocator: std.mem.Allocator) IntegerListElement {
        return IntegerListElement{
            .values = std.ArrayList(u64).init(allocator),
        };
    }

    /// Add a value
    pub fn add(self: *IntegerListElement, value: u64) !void {
        try self.values.append(value);
    }

    /// Get values
    pub fn getValues(self: *const IntegerListElement) []u64 {
        return self.values.items;
    }

    /// Deinitialize
    pub fn deinit(self: *IntegerListElement) void {
        self.values.deinit();
    }
};
