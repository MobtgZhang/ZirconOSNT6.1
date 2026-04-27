//! Registry Hive Merge Operations
//! 
//! Provides merging capabilities for two registry hives.

const std = @import("std");
const key = @import("key.zig");

/// Merge options
pub const MergeOptions = struct {
    /// Overwrite existing keys
    overwrite: bool = false,

    /// Merge values
    merge_values: bool = true,

    /// Preserve conflicts
    preserve_conflicts: bool = true,

    /// Include volatile keys
    include_volatile: bool = true,
};

/// Merge conflict information
pub const ConflictInfo = struct {
    /// Source key path
    source_path: []u8,

    /// Destination key path
    dest_path: []u8,

    /// Conflict type
    conflict_type: ConflictType,
};

/// Conflict type
pub const ConflictType = enum {
    /// Key exists in both
    KeyExists,

    /// Value exists in both
    ValueExists,

    /// Key type mismatch
    TypeMismatch,

    /// Permission denied
    AccessDenied,
};

/// Merge result
pub const MergeResult = struct {
    /// Number of merged keys
    merged_keys: u32,

    /// Number of merged values
    merged_values: u32,

    /// Number of skipped keys
    skipped_keys: u32,

    /// Number of skipped values
    skipped_values: u32,

    /// Conflicts detected
    conflicts: std.ArrayList(ConflictInfo),

    /// Errors encountered
    errors: std.ArrayList(MergeError),

    /// Create a new merge result
    pub fn init(allocator: std.mem.Allocator) MergeResult {
        return MergeResult{
            .merged_keys = 0,
            .merged_values = 0,
            .skipped_keys = 0,
            .skipped_values = 0,
            .conflicts = std.ArrayList(ConflictInfo).init(allocator),
            .errors = std.ArrayList(MergeError).init(allocator),
        };
    }

    /// Deinitialize
    pub fn deinit(result: *MergeResult) void {
        for (result.conflicts.items) |*c| {
            std.heap.page_allocator.free(c.source_path);
            std.heap.page_allocator.free(c.dest_path);
        }
        result.conflicts.deinit();
        result.errors.deinit();
    }
};

/// Merge error information
pub const MergeError = struct {
    /// Error message
    message: []u8,

    /// Key path
    path: []u8,
};

/// Merge two hives
pub fn mergeHives(
    source: *key.HiveContext,
    dest: *key.HiveContext,
    options: MergeOptions,
    allocator: std.mem.Allocator,
) !MergeResult {
    var result = MergeResult.init(allocator);

    const source_root = try source.openKey("\\");
    defer source_root.close();

    const dest_root = try dest.openKey("\\");
    defer dest_root.close();

    try mergeKeyRecursive(source_root, dest_root, options, &result, allocator);

    return result;
}

fn mergeKeyRecursive(
    source: *key.Key,
    dest_parent: *key.Key,
    options: MergeOptions,
    result: *MergeResult,
    allocator: std.mem.Allocator,
) !void {
    const source_path = try source.getFullPath(allocator);
    defer allocator.free(source_path);

    var dest_key: ?*key.Key = null;
    const existing = try dest_parent.hive.openKey(source.getName());
    if (existing) |ek| {
        if (options.overwrite) {
            try ek.delete();
            ek.close();
        } else {
            dest_key = ek;
            try result.conflicts.append(.{
                .source_path = try allocator.dupe(u8, source_path),
                .dest_path = try allocator.dupe(u8, source_path),
                .conflict_type = .KeyExists,
            });
            result.skipped_keys += 1;
        }
    }

    if (dest_key == null) {
        dest_key = try dest_parent.hive.createKey(source_path);
        result.merged_keys += 1;

        if (options.merge_values) {
            try mergeValues(source, dest_key.?, result, allocator);
        }
    }

    if (dest_key) |dk| {
        const subkeys = try source.enumerateSubkeys(allocator);
        defer {
            for (subkeys) |sk| allocator.free(sk.name);
            allocator.free(subkeys);
        }

        for (subkeys) |subkey_info| {
            const subkey = try source.hive.openKey(subkey_info.name);
            defer subkey.close();

            try mergeKeyRecursive(subkey, dk, options, result, allocator);
        }

        dk.close();
    }
}

fn mergeValues(
    source: *key.Key,
    dest: *key.Key,
    result: *MergeResult,
    allocator: std.mem.Allocator,
) !void {
    const source_values = try source.enumerateValues(allocator);
    defer {
        for (source_values) |v| allocator.free(v.name);
        allocator.free(source_values);
    }

    for (source_values) |value_info| {
        const value = try source.getValue(value_info.name);
        errdefer {
            allocator.free(value.name);
            allocator.free(value.data);
        }

        try dest.setValue(&value);
        result.merged_values += 1;

        allocator.free(value.name);
        allocator.free(value.data);
    }
}

/// Merge a specific key tree
pub fn mergeKey(
    source: *key.Key,
    dest_parent: *key.Key,
    options: MergeOptions,
    allocator: std.mem.Allocator,
) !MergeResult {
    var result = MergeResult.init(allocator);
    try mergeKeyRecursive(source, dest_parent, options, &result, allocator);
    return result;
}

/// Detect conflicts between two hives
pub fn detectConflicts(
    source: *key.HiveContext,
    dest: *key.HiveContext,
    allocator: std.mem.Allocator,
) !std.ArrayList(ConflictInfo) {
    var conflicts = std.ArrayList(ConflictInfo).init(allocator);

    const source_root = try source.openKey("\\");
    defer source_root.close();

    const dest_root = try dest.openKey("\\");
    defer dest_root.close();

    try detectConflictsRecursive(source_root, dest_root, &conflicts, allocator);

    return conflicts;
}

fn detectConflictsRecursive(
    source: *key.Key,
    dest: *key.Key,
    conflicts: *std.ArrayList(ConflictInfo),
    allocator: std.mem.Allocator,
) !void {
    const source_path = try source.getFullPath(allocator);
    defer allocator.free(source_path);

    if (dest != null) {
        try conflicts.append(.{
            .source_path = try allocator.dupe(u8, source_path),
            .dest_path = try allocator.dupe(u8, source_path),
            .conflict_type = .KeyExists,
        });
    }

    const subkeys = try source.enumerateSubkeys(allocator);
    defer {
        for (subkeys) |sk| allocator.free(sk.name);
        allocator.free(subkeys);
    }

    for (subkeys) |subkey_info| {
        const subkey = try source.hive.openKey(subkey_info.name);
        defer subkey.close();

        var dest_subkey: ?*key.Key = null;
        if (dest) |d| {
            dest_subkey = d.hive.openKey(subkey_info.name) catch null;
            if (dest_subkey) |ds| {
                try detectConflictsRecursive(subkey, ds, conflicts, allocator);
                ds.close();
            }
        }

        if (dest_subkey == null) {
            try detectConflictsRecursive(subkey, null, conflicts, allocator);
        }
    }
}

/// Resolve a conflict with a given resolution
pub fn resolveConflict(
    result: *MergeResult,
    conflict_index: usize,
    resolution: ConflictResolution,
) void {
    if (conflict_index >= result.conflicts.items.len) return;

    _ = &result.conflicts.items[conflict_index];
    switch (resolution) {
        .Skip => {
            result.skipped_keys += 1;
        },
        .Overwrite => {
            result.merged_keys += 1;
        },
        .Rename => {
            result.merged_keys += 1;
        },
    }
}

/// Conflict resolution
pub const ConflictResolution = enum {
    /// Skip the conflicting item
    Skip,

    /// Overwrite with source
    Overwrite,

    /// Rename to avoid conflict
    Rename,
};

/// Copy a key subtree to destination
pub fn copySubtree(
    source: *key.Key,
    dest_parent: *key.Key,
    allocator: std.mem.Allocator,
) !void {
    const options = MergeOptions{
        .overwrite = false,
        .merge_values = true,
        .preserve_conflicts = false,
        .include_volatile = true,
    };

    _ = options;
    const source_path = try source.getFullPath(allocator);
    defer allocator.free(source_path);

    const new_key = try dest_parent.hive.createKey(source_path);

    const values = try source.enumerateValues(allocator);
    defer {
        for (values) |v| allocator.free(v.name);
        allocator.free(values);
    }

    for (values) |value_info| {
        const value = try source.getValue(value_info.name);
        try new_key.setValue(&value);
        allocator.free(value.name);
        allocator.free(value.data);
    }

    const subkeys = try source.enumerateSubkeys(allocator);
    defer {
        for (subkeys) |sk| allocator.free(sk.name);
        allocator.free(subkeys);
    }

    for (subkeys) |subkey_info| {
        const subkey = try source.hive.openKey(subkey_info.name);
        defer subkey.close();
        try copySubtree(subkey, new_key, allocator);
    }

    new_key.close();
}
