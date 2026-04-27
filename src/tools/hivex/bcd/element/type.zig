//! BCD Element Type Definitions
//! 
//! Defines all BCD element types.

const std = @import("std");
const Self = @This();

/// Element type constants
pub const ElementType = u32;

/// Common element types
pub const Common = struct {
    // Device elements (0x11xxxxxx)
    /// Device description
    pub const DEVICE_DESCRIPTION: ElementType = 0x11000001;
    /// Boot device
    pub const BOOT_DEVICE: ElementType = 0x11000002;
    /// OS device
    pub const OS_DEVICE: ElementType = 0x11000003;
    /// File system device
    pub const FS_DEVICE: ElementType = 0x11000004;
    /// Boot loader
    pub const BOOT_LOADER: ElementType = 0x11000005;
    /// Resume application
    pub const RESUME_LOADER: ElementType = 0x11000007;
    /// RAM disk options
    pub const RAMDISK_IMAGE_OFFSET: ElementType = 0x11000010;
    pub const RAMDISK_IMAGE_LENGTH: ElementType = 0x11000011;
    pub const RAMDISK_DEVICE: ElementType = 0x11000012;

    // Integer elements (0x12xxxxxx)
    /// Timeout
    pub const TIMEOUT: ElementType = 0x12000001;
    /// Boot sequence
    pub const BOOT_SEQUENCE: ElementType = 0x12000002;
    /// Debugger port
    pub const DEBUGGER_PORT: ElementType = 0x12000010;
    /// Debugger baudrate
    pub const DEBUGGER_BAUDRATE: ElementType = 0x12000011;
    /// Debugger type
    pub const DEBUGGER_TYPE: ElementType = 0x12000012;

    // Boolean elements (0x13xxxxxx)
    /// Enable boot logo
    pub const BOOT_LOGO: ElementType = 0x13000001;
    /// Display boot menu
    pub const DISPLAY_BOOT_MENU: ElementType = 0x13000002;
    /// No error display
    pub const NO_ERROR_DISPLAY: ElementType = 0x13000003;
    /// Allow testsigning
    pub const ALLOW_TESTSIGNING: ElementType = 0x13000004;
    /// Disable bios DMA
    pub const DISABLE_BIOS_DMA: ElementType = 0x13000005;
    /// Debugger
    pub const DEBUGGER: ElementType = 0x13000006;
    /// OS debug
    pub const OS_DEBUG: ElementType = 0x13000007;
    /// PAE
    pub const PAE: ElementType = 0x13000008;
    /// Detect HAL
    pub const DETECT_HAL: ElementType = 0x13000009;
    /// Debug
    pub const DEBUG: ElementType = 0x1300000A;

    // String elements (0x15xxxxxx)
    /// Boot menu text
    pub const BOOT_MENU_TEXT: ElementType = 0x15000001;
    /// Status text
    pub const STATUS_TEXT: ElementType = 0x15000002;
    /// Boot device text
    pub const BOOT_DEVICE_TEXT: ElementType = 0x15000003;
    /// Application path
    pub const APP_PATH: ElementType = 0x15000004;
    /// OS device partition
    pub const OS_DEVICE_PARTITION: ElementType = 0x15000005;
    /// System root
    pub const SYSTEM_ROOT: ElementType = 0x15000006;
    /// Loader path
    pub const LOADER_PATH: ElementType = 0x15000007;
    /// Kernel path
    pub const KERNEL_PATH: ElementType = 0x15000008;
    /// Initrd path
    pub const INITRD_PATH: ElementType = 0x15000009;

    // Object list elements (0x17xxxxxx)
    /// Boot sequence
    pub const BOOT_SEQUENCE_OBJECT_LIST: ElementType = 0x17000001;
    /// Resume sequence
    pub const RESUME_SEQUENCE: ElementType = 0x17000002;
    /// Objects
    pub const OBJECTS: ElementType = 0x17000003;

    // Object elements (0x19xxxxxx)
    /// Inherited objects
    pub const INHERITED_OBJECTS: ElementType = 0x19000001;
};

/// Element type categories
pub const Category = enum {
    /// Device element (0x11xxxxxx)
    Device,
    /// Integer element (0x12xxxxxx)
    Integer,
    /// Boolean element (0x13xxxxxx)
    Boolean,
    /// String element (0x15xxxxxx)
    String,
    /// Object list element (0x17xxxxxx)
    ObjectList,
    /// Object element (0x19xxxxxx)
    Object,
    /// Unknown
    Unknown,
};

/// Get category from element type
pub fn getCategory(element_type: ElementType) Category {
    const major = (element_type >> 24) & 0xFF;
    return switch (major) {
        0x11 => .Device,
        0x12 => .Integer,
        0x13 => .Boolean,
        0x15 => .String,
        0x17 => .ObjectList,
        0x19 => .Object,
        else => .Unknown,
    };
}

/// Get name of an element type
pub fn getName(element_type: ElementType) ?[]const u8 {
    return switch (element_type) {
        Common.DEVICE_DESCRIPTION => "Device Description",
        Common.BOOT_DEVICE => "Boot Device",
        Common.OS_DEVICE => "OS Device",
        Common.FS_DEVICE => "File System Device",
        Common.BOOT_LOADER => "Boot Loader",
        Common.RESUME_LOADER => "Resume Loader",
        Common.RAMDISK_IMAGE_OFFSET => "RAM Disk Image Offset",
        Common.RAMDISK_IMAGE_LENGTH => "RAM Disk Image Length",
        Common.RAMDISK_DEVICE => "RAM Disk Device",
        Common.TIMEOUT => "Timeout",
        Common.BOOT_SEQUENCE => "Boot Sequence",
        Common.DEBUGGER_PORT => "Debugger Port",
        Common.DEBUGGER_BAUDRATE => "Debugger Baudrate",
        Common.DEBUGGER_TYPE => "Debugger Type",
        Common.BOOT_LOGO => "Boot Logo",
        Common.DISPLAY_BOOT_MENU => "Display Boot Menu",
        Common.NO_ERROR_DISPLAY => "No Error Display",
        Common.ALLOW_TESTSIGNING => "Allow Test Signing",
        Common.DISABLE_BIOS_DMA => "Disable BIOS DMA",
        Common.DEBUGGER => "Debugger",
        Common.OS_DEBUG => "OS Debug",
        Common.PAE => "PAE",
        Common.DETECT_HAL => "Detect HAL",
        Common.DEBUG => "Debug",
        Common.BOOT_MENU_TEXT => "Boot Menu Text",
        Common.STATUS_TEXT => "Status Text",
        Common.BOOT_DEVICE_TEXT => "Boot Device Text",
        Common.APP_PATH => "Application Path",
        Common.OS_DEVICE_PARTITION => "OS Device Partition",
        Common.SYSTEM_ROOT => "System Root",
        Common.LOADER_PATH => "Loader Path",
        Common.KERNEL_PATH => "Kernel Path",
        Common.INITRD_PATH => "Initrd Path",
        Common.BOOT_SEQUENCE_OBJECT_LIST => "Boot Sequence Object List",
        Common.RESUME_SEQUENCE => "Resume Sequence",
        Common.OBJECTS => "Objects",
        Common.INHERITED_OBJECTS => "Inherited Objects",
        else => null,
    };
}

/// Check if element type is valid
pub fn isValid(element_type: ElementType) bool {
    const category = getCategory(element_type);
    return category != .Unknown;
}

/// Check if element is device type
pub fn isDevice(element_type: ElementType) bool {
    return getCategory(element_type) == .Device;
}

/// Check if element is integer type
pub fn isInteger(element_type: ElementType) bool {
    return getCategory(element_type) == .Integer;
}

/// Check if element is boolean type
pub fn isBoolean(element_type: ElementType) bool {
    return getCategory(element_type) == .Boolean;
}

/// Check if element is string type
pub fn isString(element_type: ElementType) bool {
    return getCategory(element_type) == .String;
}

/// Check if element is object list type
pub fn isObjectList(element_type: ElementType) bool {
    return getCategory(element_type) == .ObjectList;
}
