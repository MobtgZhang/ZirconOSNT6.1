//! Registry Library Root Module
//! 
//! This module exports all registry-related types and functions.

const Self = @This();

/// Re-export key module
pub const Key = @import("key.zig");
pub const key = @import("key.zig");

/// Re-export value module
pub const Value = @import("value.zig");
pub const value = @import("value.zig");

/// Re-export tree module
pub const Tree = @import("tree.zig");
pub const tree = @import("tree.zig");

/// Re-export query module
pub const Query = @import("query.zig");
pub const query = @import("query.zig");

/// Re-export merge module
pub const Merge = @import("merge.zig");
pub const merge = @import("merge.zig");

/// Re-export diff module
pub const Diff = @import("diff.zig");
pub const diff = @import("diff.zig");

/// Registry context
pub const RegistryContext = key.HiveContext;

/// Error types
pub const Error = error{
    KeyNotFound,
    ValueNotFound,
    AccessDenied,
    InvalidParameter,
    OutOfMemory,
    IoError,
    InvalidPath,
    ConflictDetected,
};
