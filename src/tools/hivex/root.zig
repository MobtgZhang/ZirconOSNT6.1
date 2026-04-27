//! Hivex Library Root Module
//! 
//! A comprehensive library for Windows Registry Hive and BCD file manipulation.

const std = @import("std");

// Re-export hive module
pub const hive = struct {
    pub const Hive = @import("hive/root.zig").Hive;
    pub const HiveHeader = @import("hive/header.zig").HiveHeader;
    pub const HbinBlock = @import("hive/hbin.zig").HbinBlock;
    pub const Cell = @import("hive/cell.zig").Cell;
    pub const CellAllocator = @import("hive/cell.zig").CellAllocator;
    pub const NkCell = @import("hive/nk.zig").NkCell;
    pub const NkCellHeader = @import("hive/nk.zig").Header;
    pub const VkCell = @import("hive/vk.zig").VkCell;
    pub const VkCellHeader = @import("hive/vk.zig").Header;
    pub const SkCell = @import("hive/sk.zig").SkCell;
    pub const LfCell = @import("hive/lf.zig").LfCell;
    pub const RiCell = @import("hive/ri.zig").RiCell;
    pub const DbCell = @import("hive/db.zig").DbCell;
    pub const HiveLog = @import("hive/log.zig").HiveLog;
};

// Re-export registry module
pub const registry = struct {
    pub const HiveContext = @import("registry/key.zig").HiveContext;
    pub const Key = @import("registry/key.zig").Key;
    pub const Value = @import("registry/value.zig").Value;
    pub const KeyInfo = @import("registry/key.zig").KeyInfo;
    pub const SubkeyInfo = @import("registry/key.zig").SubkeyInfo;
    pub const ValueInfo = @import("registry/key.zig").ValueInfo;
    pub const TreeIterator = @import("registry/tree.zig").TreeIterator;
    pub const DiffResult = @import("registry/diff.zig").DiffResult;
    pub const MergeResult = @import("registry/merge.zig").MergeResult;
};

// Re-export bcd module
pub const bcd = struct {
    pub const BcdStore = @import("bcd/store.zig").BcdStore;
    pub const BcdObject = @import("bcd/object/object.zig").Object;
    pub const BcdElement = @import("bcd/object/object.zig").Element;
    pub const GUID = @import("bcd/object/guid.zig").GUID;
    pub const ObjectType = @import("bcd/object/type.zig").ObjectType;
    pub const ElementType = @import("bcd/element/type.zig").ElementType;
    pub const getElementTypeCategory = @import("bcd/element/type.zig").getCategory;
    pub const WellKnownGuid = @import("bcd/object/guid.zig").WellKnownGuid;
    pub const BcdReader = @import("bcd/parser/reader.zig").Reader;
    pub const BcdWriter = @import("bcd/parser/writer.zig").Writer;
    pub const BcdTextWriter = @import("bcd/parser/text.zig").TextWriter;
    pub const BcdTextFormat = @import("bcd/parser/text.zig").Format;
    pub const BcdJsonWriter = @import("bcd/parser/json.zig").JsonWriter;
    pub const text = @import("bcd/parser/text.zig");
    pub const WindowsTemplate = @import("bcd/template/windows.zig").WindowsTemplate;
    pub const RecoveryTemplate = @import("bcd/template/recovery.zig").RecoveryTemplate;
    pub const ZirconOsTemplate = @import("bcd/template/zirconos.zig").ZirconOsTemplate;
};

// Re-export version info
pub const version = struct {
    pub const major: u32 = 1;
    pub const minor: u32 = 0;
    pub const patch: u32 = 0;
    pub const string = "1.0.0";
};

/// Hivex error types
pub const Error = error{
    InvalidHeader,
    InvalidSignature,
    InvalidVersion,
    BufferTooSmall,
    FileNotFound,
    PermissionDenied,
    IoError,
    InvalidCell,
    CellOverflow,
    OutOfMemory,
    KeyNotFound,
    ValueNotFound,
    AccessDenied,
    InvalidParameter,
    InvalidPath,
    ConflictDetected,
    ObjectNotFound,
    InvalidStore,
    InvalidTemplate,
};

/// Initialize hivex library
pub fn init() void {
    // No global initialization needed
}

/// Deinitialize hivex library
pub fn deinit() void {
    // No global cleanup needed
}

/// Get library version string
pub fn getVersionString() [:0]const u8 {
    return version.string;
}

/// Get library version components
pub fn getVersion() struct { major: u32, minor: u32, patch: u32 } {
    return .{ .major = version.major, .minor = version.minor, .patch = version.patch };
}

/// CLI argument parsing helper for Zig 0.16.0+
/// Returns slice of command line arguments (excluding program name)
/// Note: This is a placeholder that returns empty args.
/// CLI tools should implement their own argument parsing.
pub fn getCliArgs() []const []const u8 {
    return &.{};
}
