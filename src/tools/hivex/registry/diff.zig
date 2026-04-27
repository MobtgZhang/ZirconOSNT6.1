//! Registry Hive Diff Operations
//! 
//! Provides diff capabilities for comparing two registry hives.

const std = @import("std");
const key = @import("key.zig");
const vk = @import("../hive/vk.zig");

/// Diff options
pub const DiffOptions = struct {
    /// Compare values
    compare_values: bool = true,

    /// Compare timestamps
    compare_timestamps: bool = false,

    /// Ignore case in names
    ignore_case: bool = true,

    /// Include volatile keys
    include_volatile: bool = true,
};

/// Diff result
pub const DiffResult = struct {
    /// Keys added in source
    added_keys: std.ArrayList(KeyInfo),

    /// Keys removed from source
    removed_keys: std.ArrayList(KeyInfo),

    /// Keys modified
    modified_keys: std.ArrayList(ModifiedKeyInfo),

    /// Values added
    added_values: std.ArrayList(ValueInfo),

    /// Values removed
    removed_values: std.ArrayList(ValueInfo),

    /// Values modified
    modified_values: std.ArrayList(ModifiedValueInfo),

    /// Create a new diff result
    pub fn init(allocator: std.mem.Allocator) DiffResult {
        return DiffResult{
            .added_keys = std.ArrayList(KeyInfo).init(allocator),
            .removed_keys = std.ArrayList(KeyInfo).init(allocator),
            .modified_keys = std.ArrayList(ModifiedKeyInfo).init(allocator),
            .added_values = std.ArrayList(ValueInfo).init(allocator),
            .removed_values = std.ArrayList(ValueInfo).init(allocator),
            .modified_values = std.ArrayList(ModifiedValueInfo).init(allocator),
        };
    }

    /// Deinitialize
    pub fn deinit(result: *DiffResult) void {
        for (result.added_keys.items) |*ki| {
            std.heap.page_allocator.free(ki.path);
        }
        for (result.removed_keys.items) |*ki| {
            std.heap.page_allocator.free(ki.path);
        }
        for (result.modified_keys.items) |*mki| {
            std.heap.page_allocator.free(mki.path);
            for (mki.changes) |*c| {
                std.heap.page_allocator.free(c.description);
            }
            std.heap.page_allocator.free(mki.changes);
        }
        for (result.added_values.items) |*vi| {
            std.heap.page_allocator.free(vi.key_path);
            std.heap.page_allocator.free(vi.value_name);
        }
        for (result.removed_values.items) |*vi| {
            std.heap.page_allocator.free(vi.key_path);
            std.heap.page_allocator.free(vi.value_name);
        }
        for (result.modified_values.items) |*mvi| {
            std.heap.page_allocator.free(mvi.key_path);
            std.heap.page_allocator.free(mvi.value_name);
            std.heap.page_allocator.free(mvi.old_value.data);
            std.heap.page_allocator.free(mvi.new_value.data);
        }
        result.added_keys.deinit();
        result.removed_keys.deinit();
        result.modified_keys.deinit();
        result.added_values.deinit();
        result.removed_values.deinit();
        result.modified_values.deinit();
    }

    /// Get total change count
    pub fn getChangeCount(result: *const DiffResult) u32 {
        return @as(u32, @intCast(
            result.added_keys.items.len +
            result.removed_keys.items.len +
            result.modified_keys.items.len +
            result.added_values.items.len +
            result.removed_values.items.len +
            result.modified_values.items.len
        ));
    }
};

/// Key basic info
pub const KeyBasicInfo = struct {
    /// Subkey count
    subkey_count: u32,

    /// Value count
    value_count: u32,

    /// Timestamp
    timestamp: u64,
};

/// Key info for diff
pub const KeyInfo = struct {
    /// Key path
    path: []u8,

    /// Key info
    info: KeyBasicInfo,
};

/// Modified key info
pub const ModifiedKeyInfo = struct {
    /// Key path
    path: []u8,

    /// Changes
    changes: []ChangeInfo,
};

/// Change info
pub const ChangeInfo = struct {
    /// Change type
    change_type: ChangeType,

    /// Description
    description: []u8,
};

/// Change type
pub const ChangeType = enum {
    /// Key timestamp changed
    TimestampChanged,

    /// Key subkey count changed
    SubkeyCountChanged,

    /// Key value count changed
    ValueCountChanged,
};

/// Value info for diff
pub const ValueInfo = struct {
    /// Key path
    key_path: []u8,

    /// Value name
    value_name: []u8,

    /// Value type
    value_type: vk.ValueType,

    /// Value data
    data: []u8,
};

/// Modified value info
pub const ModifiedValueInfo = struct {
    /// Key path
    key_path: []u8,

    /// Value name
    value_name: []u8,

    /// Old value
    old_value: ValueInfo,

    /// New value
    new_value: ValueInfo,
};

/// Compare two hives
pub fn diffHives(
    source: *key.HiveContext,
    dest: *key.HiveContext,
    options: DiffOptions,
    allocator: std.mem.Allocator,
) !DiffResult {
    var result = DiffResult.init(allocator);

    const source_root = try source.openKey("\\");
    defer source_root.close();

    const dest_root = try dest.openKey("\\");
    defer dest_root.close();

    try diffKeysRecursive(source_root, dest_root, options, &result, allocator);

    return result;
}

fn diffKeysRecursive(
    source: *key.Key,
    dest: *key.Key,
    options: DiffOptions,
    result: *DiffResult,
    allocator: std.mem.Allocator,
) !void {
    const source_path = try source.getFullPath(allocator);
    defer allocator.free(source_path);

    const dest_path = if (dest != null) try dest.getFullPath(allocator) else null;
    defer if (dest_path) |dp| allocator.free(dp);

    if (dest == null) {
        const info = try source.getInfo();
        try result.added_keys.append(.{
            .path = try allocator.dupe(u8, source_path),
            .info = .{
                .subkey_count = info.subkey_count,
                .value_count = info.value_count,
                .timestamp = info.timestamp,
            },
        });
    } else {
        const source_info = try source.getInfo();
        const dest_info = try dest.getInfo();

        if (options.compare_timestamps and source_info.timestamp != dest_info.timestamp) {
            try result.modified_keys.append(.{
                .path = try allocator.dupe(u8, source_path),
                .changes = try allocator.alloc(ChangeInfo, 1),
            });
            result.modified_keys.items[result.modified_keys.items.len - 1].changes[0] = .{
                .change_type = .TimestampChanged,
                .description = try allocator.dupe(u8, "Timestamp changed"),
            };
        }
    }

    if (options.compare_values and dest != null) {
        try diffValues(source, dest.?, options, result, allocator);
    }

    const source_subkeys = try source.enumerateSubkeys(allocator);
    defer {
        for (source_subkeys) |sk| allocator.free(sk.name);
        allocator.free(source_subkeys);
    }

    var dest_subkeys_map = std.StringHashMap(*key.Key).init(allocator);
    defer {
        var it = dest_subkeys_map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.close();
        }
        dest_subkeys_map.deinit();
    }

    if (dest != null) {
        const dest_subkeys = try dest.enumerateSubkeys(allocator);
        defer {
            for (dest_subkeys) |sk| allocator.free(sk.name);
            allocator.free(dest_subkeys);
        }

        for (dest_subkeys) |subkey_info| {
            const subkey = try dest.hive.openKey(subkey_info.name);
            const name = if (options.ignore_case) try allocator.dupe(u8, subkey_info.name) else subkey_info.name;
            try dest_subkeys_map.put(name, subkey);
        }
    }

    for (source_subkeys) |subkey_info| {
        const name = if (options.ignore_case) try allocator.dupe(u8, subkey_info.name) else subkey_info.name;
        const subkey = try source.hive.openKey(subkey_info.name);
        defer subkey.close();

        if (dest_subkeys_map.get(name)) |dest_subkey| {
            try diffKeysRecursive(subkey, dest_subkey, options, result, allocator);
            _ = dest_subkeys_map.remove(name);
        } else {
            try diffKeysRecursive(subkey, null, options, result, allocator);
        }

        if (options.ignore_case) {
            allocator.free(name);
        }
    }

    var it = dest_subkeys_map.iterator();
    while (it.next()) |entry| {
        const dest_path_full = try entry.value_ptr.*.getFullPath(allocator);
        const info = try entry.value_ptr.*.getInfo();
        try result.removed_keys.append(.{
            .path = dest_path_full,
            .info = .{
                .subkey_count = info.subkey_count,
                .value_count = info.value_count,
                .timestamp = info.timestamp,
            },
        });
        allocator.free(entry.key_ptr.*);
    }
}

fn diffValues(
    source: *key.Key,
    dest: *key.Key,
    options: DiffOptions,
    result: *DiffResult,
    allocator: std.mem.Allocator,
) !void {
    const source_path = try source.getFullPath(allocator);
    defer allocator.free(source_path);

    const dest_path = try dest.getFullPath(allocator);
    defer allocator.free(dest_path);

    const source_values = try source.enumerateValues(allocator);
    defer {
        for (source_values) |v| allocator.free(v.name);
        allocator.free(source_values);
    }

    var dest_values_map = std.StringHashMap(key.ValueInfo).init(allocator);
    defer dest_values_map.deinit();

    const dest_values = try dest.enumerateValues(allocator);
    defer {
        for (dest_values) |v| allocator.free(v.name);
        allocator.free(dest_values);
    }

    for (dest_values) |value_info| {
        const value = try dest.getValue(value_info.name);
        const name = if (options.ignore_case) try allocator.dupe(u8, value_info.name) else value_info.name;
        try dest_values_map.put(name, value);
    }

    for (source_values) |value_info| {
        const name = if (options.ignore_case) try allocator.dupe(u8, value_info.name) else value_info.name;
        const value = try source.getValue(value_info.name);

        if (dest_values_map.get(name)) |dest_value| {
            if (!std.mem.eql(u8, value.data, dest_value.data)) {
                try result.modified_values.append(.{
                    .key_path = try allocator.dupe(u8, source_path),
                    .value_name = try allocator.dupe(u8, name),
                    .old_value = .{
                        .key_path = try allocator.dupe(u8, dest_path),
                        .value_name = try allocator.dupe(u8, dest_value.name),
                        .value_type = dest_value.value_type,
                        .data = dest_value.data,
                    },
                    .new_value = .{
                        .key_path = try allocator.dupe(u8, source_path),
                        .value_name = try allocator.dupe(u8, name),
                        .value_type = value.value_type,
                        .data = try allocator.dupe(u8, value.data),
                    },
                });
            }
            _ = dest_values_map.remove(name);
        } else {
            try result.added_values.append(.{
                .key_path = try allocator.dupe(u8, source_path),
                .value_name = try allocator.dupe(u8, name),
                .value_type = value.value_type,
                .data = try allocator.dupe(u8, value.data),
            });
        }

        allocator.free(value.name);
        allocator.free(value.data);
        if (options.ignore_case) {
            allocator.free(name);
        }
    }

    var it = dest_values_map.iterator();
    while (it.next()) |entry| {
        try result.removed_values.append(.{
            .key_path = try allocator.dupe(u8, dest_path),
            .value_name = entry.key_ptr.*,
            .value_type = entry.value_ptr.*.value_type,
            .data = entry.value_ptr.*.data,
        });
    }
}

/// Format diff result as text
pub fn formatDiffText(result: *const DiffResult, allocator: std.mem.Allocator) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();

    try writer.print("Registry Diff Results\n", .{});
    try writer.print("====================\n\n", .{});

    if (result.added_keys.items.len > 0) {
        try writer.print("Added Keys:\n", .{});
        for (result.added_keys.items) |ki| {
            try writer.print("  + {s}\n", .{ki.path});
        }
        try writer.print("\n", .{});
    }

    if (result.removed_keys.items.len > 0) {
        try writer.print("Removed Keys:\n", .{});
        for (result.removed_keys.items) |ki| {
            try writer.print("  - {s}\n", .{ki.path});
        }
        try writer.print("\n", .{});
    }

    if (result.modified_keys.items.len > 0) {
        try writer.print("Modified Keys:\n", .{});
        for (result.modified_keys.items) |mki| {
            try writer.print("  ~ {s}\n", .{mki.path});
            for (mki.changes) |c| {
                try writer.print("      {s}\n", .{c.description});
            }
        }
        try writer.print("\n", .{});
    }

    if (result.added_values.items.len > 0) {
        try writer.print("Added Values:\n", .{});
        for (result.added_values.items) |vi| {
            try writer.print("  + {s}\\{s}\n", .{vi.key_path, vi.value_name});
        }
        try writer.print("\n", .{});
    }

    if (result.removed_values.items.len > 0) {
        try writer.print("Removed Values:\n", .{});
        for (result.removed_values.items) |vi| {
            try writer.print("  - {s}\\{s}\n", .{vi.key_path, vi.value_name});
        }
        try writer.print("\n", .{});
    }

    if (result.modified_values.items.len > 0) {
        try writer.print("Modified Values:\n", .{});
        for (result.modified_values.items) |mvi| {
            try writer.print("  ~ {s}\\{s}\n", .{mvi.key_path, mvi.value_name});
        }
    }

    return buf.toOwnedSlice();
}
