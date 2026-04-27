//! BCD Object Type Definitions
//! 
//! Defines all BCD object types.

const Self = @This();

/// BCD Object Types
pub const ObjectType = enum(u32) {
    /// Unknown object type
    Unknown = 0x00000000,

    // Firmware objects (0x01000000 - 0x01FFFFFF)
    /// Firmware boot application
    FirmwareBootApplication = 0x01000000,
    /// Firmware boot manager
    FirmwareBootManager = 0x01000001,
    /// Firmware driver
    FirmwareDriver = 0x01000002,
    /// Firmware resource
    FirmwareResource = 0x01000003,
    /// Firmware application
    FirmwareApplication = 0x01000004,

    // OS Loader objects (0x1000000 - 0x10FFFFFF)
    /// OS Loader
    OsLoader = 0x01000010,
    /// OS Manager
    OsManager = 0x01000011,
    /// OS Resume (hibernation)
    OsResume = 0x01000012,
    /// OS Restart
    OsRestart = 0x01000013,

    // Setup loader objects (0x02000000 - 0x02FFFFFF)
    /// Setup loader
    SetupLoader = 0x02000010,
    /// Boot manager
    Bootmgr = 0x02000001,
    /// Boot loaders collection
    Bootloaders = 0x02000002,
    /// Resume application
    ResumeApplication = 0x02000003,
    /// Memory diagnostic
    Memdiag = 0x02000004,
    /// Recovery OS
    RecoveryOs = 0x02000005,
    /// Startup object
    StartupObject = 0x02000006,
    /// Startup module
    StartupModule = 0x02000007,
    /// Startup policy
    StartupPolicy = 0x02000008,

    // Tools objects (0x03000000 - 0x03FFFFFF)
    /// Tools
    Tools = 0x03000000,
    /// Tools application
    ToolsApplication = 0x03000001,
    /// Tools driver
    ToolsDriver = 0x03000002,
    /// Tools resource
    ToolsResource = 0x03000003,

    // Library objects (0x04000000 - 0x04FFFFFF)
    /// Library
    Library = 0x04000000,
    /// Library object
    LibraryObject = 0x04000001,
    /// Library inherit policy
    LibraryInheritPolicy = 0x04000002,
    /// Library membership policy
    LibraryMembershipPolicy = 0x04000003,

    /// Invalid object type
    Invalid = 0xFFFFFFFF,

    /// Get the category of this object type
    pub fn getCategory(self: ObjectType) ObjectCategory {
        const value = @as(u32, @intFromEnum(self));
        const major = value & 0xFF000000;
        return switch (major) {
            0x01000000 => .Firmware,
            0x02000000 => .BootManager,
            0x03000000 => .Tools,
            0x04000000 => .Library,
            else => .Unknown,
        };
    }

    /// Get the string name of this type
    pub fn getName(self: ObjectType) []const u8 {
        return switch (self) {
            .Unknown => "Unknown",
            .FirmwareBootApplication => "Firmware Boot Application",
            .FirmwareBootManager => "Firmware Boot Manager",
            .FirmwareDriver => "Firmware Driver",
            .FirmwareResource => "Firmware Resource",
            .FirmwareApplication => "Firmware Application",
            .OsLoader => "OS Loader",
            .OsManager => "OS Manager",
            .OsResume => "OS Resume",
            .OsRestart => "OS Restart",
            .SetupLoader => "Setup Loader",
            .Bootmgr => "Boot Manager",
            .Bootloaders => "Boot Loaders",
            .ResumeApplication => "Resume Application",
            .Memdiag => "Memory Diagnostic",
            .RecoveryOs => "Recovery OS",
            .StartupObject => "Startup Object",
            .StartupModule => "Startup Module",
            .StartupPolicy => "Startup Policy",
            .Tools => "Tools",
            .ToolsApplication => "Tools Application",
            .ToolsDriver => "Tools Driver",
            .ToolsResource => "Tools Resource",
            .Library => "Library",
            .LibraryObject => "Library Object",
            .LibraryInheritPolicy => "Library Inherit Policy",
            .LibraryMembershipPolicy => "Library Membership Policy",
            .Invalid => "Invalid",
        };
    }

    /// Check if this is a valid type
    pub fn isValid(self: ObjectType) bool {
        return self != .Unknown and self != .Invalid;
    }

    /// Get type from string name
    pub fn fromName(name: []const u8) ?ObjectType {
        inline for (@typeInfo(ObjectType).@"union".fields) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                return @as(ObjectType, @enumFromInt(field.value));
            }
        }
        return null;
    }
};

/// Object category
pub const ObjectCategory = enum {
    /// Firmware objects
    Firmware,
    /// Boot manager objects
    BootManager,
    /// Tools objects
    Tools,
    /// Library objects
    Library,
    /// Unknown category
    Unknown,
};

/// Get category name
pub fn getCategoryName(category: ObjectCategory) []const u8 {
    return switch (category) {
        .Firmware => "Firmware",
        .BootManager => "Boot Manager",
        .Tools => "Tools",
        .Library => "Library",
        .Unknown => "Unknown",
    };
}

/// Common object types
pub const Common = struct {
    /// Boot manager object GUID
    pub const bootmgr = ObjectType.Bootmgr;

    /// Default OS object GUID
    pub const default = ObjectType.OsLoader;

    /// Current boot entry
    pub const current = ObjectType.OsLoader;

    /// Memory diagnostic
    pub const memdiag = ObjectType.Memdiag;

    /// Resume from hibernate
    pub const resume_from_hibernate = ObjectType.OsResume;

    /// Setup/Boot
    pub const setup = ObjectType.SetupLoader;

    /// Recovery OS
    pub const recovery = ObjectType.RecoveryOs;
};

const std = @import("std");
