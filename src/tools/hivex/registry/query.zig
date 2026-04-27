//! Registry Path Query
//! 
//! Provides path-based key and value lookup operations.

const std = @import("std");
const key = @import("key.zig");

/// Query a path and return the key
pub fn queryPath(hive_ctx: *key.HiveContext, path: []const u8) !*key.Key {
    return try hive_ctx.openKey(path);
}

/// Open a key by path
pub fn openPath(hive_ctx: *key.HiveContext, path: []const u8) !*key.Key {
    if (path.len == 0) {
        return error.InvalidPath;
    }

    var components = std.mem.split(u8, path, "\\");
    var current: ?*key.Key = null;

    while (components.next()) |component| {
        if (component.len == 0) continue;

        if (current == null) {
            if (std.mem.eql(u8, component, hive_ctx.hive.path)) {
                continue;
            }
            current = try hive_ctx.openKey(component);
        } else {
            const next = try current.?.hive.openKey(component);
            current.?.close();
            current = next;
        }
    }

    return current orelse return error.KeyNotFound;
}

/// Resolve a relative path from a base key
pub fn resolveRelativePath(base: *key.Key, relative_path: []const u8) ![]u8 {
    if (relative_path.len == 0) {
        return try base.getFullPath(std.heap.page_allocator);
    }

    const base_path = try base.getFullPath(std.heap.page_allocator);
    defer std.heap.page_allocator.free(base_path);

    if (relative_path[0] == '\\') {
        return try std.heap.page_allocator.dupe(u8, relative_path);
    }

    const separator = "\\";
    const new_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}{s}{s}", .{
        base_path,
        separator,
        relative_path,
    });

    return new_path;
}

/// Resolve an absolute path
pub fn resolveAbsolutePath(_: *key.HiveContext, path: []const u8) ![]u8 {
    if (path[0] != '\\') {
        return error.InvalidPath;
    }

    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();
    try result.appendSlice(path);

    var components = std.mem.split(u8, path[1..], "\\");
    var resolved = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer resolved.deinit();

    while (components.next()) |component| {
        if (component.len == 0) continue;

        if (std.mem.eql(u8, component, ".")) {
            continue;
        } else if (std.mem.eql(u8, component, "..")) {
            if (resolved.items.len > 0) {
                _ = resolved.pop();
            }
        } else {
            try resolved.append(component);
        }
    }

    result.shrinkRetainingCapacity(0);
    try result.append('\\');

    for (resolved.items, 0..) |comp, i| {
        if (i > 0) try result.append('\\');
        try result.appendSlice(comp);
    }

    return result.toOwnedSlice();
}

/// Find a key by name (case-insensitive)
pub fn findKey(parent: *key.Key, name: []const u8, allocator: std.mem.Allocator) !?*key.Key {
    const subkeys = try parent.enumerateSubkeys(allocator);
    defer {
        for (subkeys) |sk| allocator.free(sk.name);
        allocator.free(subkeys);
    }

    for (subkeys) |subkey_info| {
        if (std.ascii.eqlIgnoreCase(subkey_info.name, name)) {
            return try parent.hive.openKey(subkey_info.name);
        }
    }

    return null;
}

/// Find a value by name (case-insensitive)
pub fn findValue(parent: *key.Key, name: []const u8, allocator: std.mem.Allocator) !?key.Value {
    const values = try parent.enumerateValues(allocator);
    defer {
        for (values) |v| allocator.free(v.name);
        allocator.free(values);
    }

    for (values) |value_info| {
        if (std.ascii.eqlIgnoreCase(value_info.name, name)) {
            return try parent.getValue(value_info.name);
        }
    }

    return null;
}

/// Search for keys matching a pattern
pub fn searchKeys(parent: *key.Key, pattern: []const u8, allocator: std.mem.Allocator) ![]key.SubkeyInfo {
    var result = std.ArrayList(key.SubkeyInfo).init(allocator);
    const subkeys = try parent.enumerateSubkeys(allocator);
    defer {
        for (subkeys) |sk| allocator.free(sk.name);
        allocator.free(subkeys);
    }

    for (subkeys) |subkey_info| {
        if (matchPattern(subkey_info.name, pattern)) {
            try result.append(subkey_info);
        }
    }

    return result.toOwnedSlice();
}

/// Simple pattern matching (supports * and ?)
fn matchPattern(name: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return true;
    if (pattern.len == 1 and pattern[0] == '*') return true;

    var name_idx: usize = 0;
    var pattern_idx: usize = 0;

    while (name_idx < name.len and pattern_idx < pattern.len) {
        switch (pattern[pattern_idx]) {
            '*' => {
                pattern_idx += 1;
                if (pattern_idx >= pattern.len) return true;
                while (name_idx < name.len) {
                    if (matchPattern(name[name_idx..], pattern[pattern_idx..])) {
                        return true;
                    }
                    name_idx += 1;
                }
                return false;
            },
            '?' => {
                name_idx += 1;
                pattern_idx += 1;
            },
            else => {
                if (std.ascii.toLower(name[name_idx]) != std.ascii.toLower(pattern[pattern_idx])) {
                    return false;
                }
                name_idx += 1;
                pattern_idx += 1;
            },
        }
    }

    return name_idx == name.len and pattern_idx == pattern.len;
}

/// Get relative path from a base key
pub fn getRelativePath(k: *key.Key, from: *key.Key, allocator: std.mem.Allocator) ![]u8 {
    const full_path = try k.getFullPath(allocator);
    defer allocator.free(full_path);

    const base_path = try from.getFullPath(allocator);
    defer allocator.free(base_path);

    if (std.mem.startsWith(u8, full_path, base_path)) {
        const suffix = full_path[base_path.len..];
        if (suffix.len > 0 and suffix[0] == '\\') {
            return allocator.dupe(u8, suffix[1..]);
        }
        return allocator.dupe(u8, suffix);
    }

    return allocator.dupe(u8, full_path);
}

/// Normalize a path (resolve . and .., remove duplicate separators)
pub fn normalizePath(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var is_absolute = false;
    if (path.len > 0 and path[0] == '\\') {
        is_absolute = true;
        try result.append('\\');
    }

    var components = std.mem.split(u8, path, "\\");
    while (components.next()) |component| {
        if (component.len == 0) continue;

        if (std.mem.eql(u8, component, ".")) {
            continue;
        } else if (std.mem.eql(u8, component, "..")) {
            if (result.items.len > 0 and !is_absolute) {
                var last_sep = result.items.len - 1;
                while (last_sep > 0 and result.items[last_sep - 1] != '\\') {
                    last_sep -= 1;
                }
                result.shrinkRetainingCapacity(last_sep);
            }
        } else {
            if (result.items.len > 0 and result.items[result.items.len - 1] != '\\') {
                try result.append('\\');
            }
            try result.appendSlice(component);
        }
    }

    return result.toOwnedSlice();
}

/// Error types
pub const Error = error{
    InvalidPath,
    KeyNotFound,
    ValueNotFound,
    OutOfMemory,
};
