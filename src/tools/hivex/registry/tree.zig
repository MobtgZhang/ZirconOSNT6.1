//! Registry Tree Traversal
//! 
//! Provides tree traversal operations for registry keys.

const std = @import("std");
const key = @import("key.zig");

/// Traversal mode
pub const TraversalMode = enum {
    /// Depth-first traversal
    DepthFirst,

    /// Breadth-first traversal
    BreadthFirst,
};

/// Tree iterator for traversing registry keys
pub const TreeIterator = struct {
    /// Traversal mode
    mode: TraversalMode,

    /// Include volatile keys
    include_volatile: bool,

    /// Current position stack (for depth-first)
    stack: std.ArrayList(*key.Key),

    /// Queue (for breadth-first)
    queue: std.ArrayList(*key.Key),

    /// Create a new tree iterator
    pub fn init(mode: TraversalMode, include_volatile: bool) TreeIterator {
        return TreeIterator{
            .mode = mode,
            .include_volatile = include_volatile,
            .stack = std.ArrayList(*key.Key).init(std.heap.page_allocator),
            .queue = std.ArrayList(*key.Key).init(std.heap.page_allocator),
        };
    }

    /// Start traversal from a key
    pub fn start(iter: *TreeIterator, root: *key.Key) !void {
        try iter.stack.append(root);
        try iter.queue.append(root);
    }

    /// Get the next key in traversal order
    pub fn next(iter: *TreeIterator) ?*key.Key {
        switch (iter.mode) {
            .DepthFirst => {
                return iter.stack.pop();
            },
            .BreadthFirst => {
                return iter.queue.shift();
            },
        }
    }

    /// Add children of a key
    pub fn addChildren(iter: *TreeIterator, parent: *key.Key, allocator: std.mem.Allocator) !void {
        const subkeys = try parent.enumerateSubkeys(allocator);
        defer {
            for (subkeys) |sk| allocator.free(sk.name);
            allocator.free(subkeys);
        }

        for (subkeys) |subkey_info| {
            const subkey = try parent.hive.openKey(subkey_info.name);
            switch (iter.mode) {
                .DepthFirst => {
                    try iter.stack.append(subkey);
                },
                .BreadthFirst => {
                    try iter.queue.append(subkey);
                },
            }
        }
    }

    /// Reset the iterator
    pub fn reset(iter: *TreeIterator) void {
        iter.stack.clearRetainingCapacity();
        iter.queue.clearRetainingCapacity();
    }

    /// Deinitialize
    pub fn deinit(iter: *TreeIterator) void {
        iter.stack.deinit();
        iter.queue.deinit();
    }
};

/// Tree visitor interface
pub const TreeVisitor = struct {
    /// Visit a key
    pub fn visit(ctx: *anyopaque, key_info: *const key.KeyInfo, depth: u32) anyerror!void {
        _ = ctx;
        _ = key_info;
        _ = depth;
    }

    /// Called before visiting children
    pub fn preChildren(ctx: *anyopaque, k: *key.Key) anyerror!void {
        _ = ctx;
        _ = k;
    }

    /// Called after visiting children
    pub fn postChildren(ctx: *anyopaque, k: *key.Key) anyerror!void {
        _ = ctx;
        _ = k;
    }
};

/// Perform depth-first traversal with visitor
pub fn depthFirstTraversal(root: *key.Key, visitor: *TreeVisitor, ctx: *anyopaque) !void {
    try visitNode(root, visitor, ctx, 0);
}

fn visitNode(k: *key.Key, visitor: *TreeVisitor, ctx: *anyopaque, depth: u32) !void {
    const info = try k.getInfo();
    try visitor.visit(ctx, &info, depth);

    try visitor.preChildren(ctx, k);
    defer visitor.postChildren(ctx, k);

    const allocator = std.heap.page_allocator;
    const subkeys = try k.enumerateSubkeys(allocator);
    defer {
        for (subkeys) |sk| allocator.free(sk.name);
        allocator.free(subkeys);
    }

    for (subkeys) |subkey_info| {
        const subkey = try k.hive.openKey(subkey_info.name);
        defer subkey.close();
        try visitNode(subkey, visitor, ctx, depth + 1);
    }
}

/// Perform breadth-first traversal with visitor
pub fn breadthFirstTraversal(root: *key.Key, visitor: *TreeVisitor, ctx: *anyopaque) !void {
    var iter = TreeIterator.init(.BreadthFirst, true);
    defer iter.deinit();

    try iter.start(root);
    var depth: u32 = 0;
    var level_count: usize = 1;

    while (iter.queue.items.len > 0) {
        var new_level_count: usize = 0;
        while (level_count > 0) {
            const k = iter.next() orelse break;
            const info = try k.getInfo();
            try visitor.visit(ctx, &info, depth);

            try iter.addChildren(k, std.heap.page_allocator);
            new_level_count += iter.stack.items.len;
            level_count -= 1;
        }
        depth += 1;
        level_count = new_level_count;
    }
}

/// Get all subkeys in a subtree
pub fn getSubtree(root: *key.Key, allocator: std.mem.Allocator) ![]key.KeyInfo {
    var result = std.ArrayList(key.KeyInfo).init(allocator);
    var iter = TreeIterator.init(.DepthFirst, true);
    defer iter.deinit();

    try iter.start(root);

    while (iter.next()) |k| {
        const info = try k.getInfo();
        try result.append(info);
    }

    return result.toOwnedSlice();
}

/// Get ancestors of a key
pub fn getAncestors(k: *const key.Key, allocator: std.mem.Allocator) ![]key.KeyInfo {
    var result = std.ArrayList(key.KeyInfo).init(allocator);
    var current: ?*const key.Key = k;

    while (current) |current_key| {
        if (current_key.parent) |parent| {
            const info = try parent.getInfo();
            try result.append(info);
            current = parent;
        } else {
            break;
        }
    }

    std.mem.reverse(key.KeyInfo, result.items);
    return result.toOwnedSlice();
}

/// Get the depth of a key in the tree
pub fn getDepth(k: *const key.Key) u32 {
    var depth: u32 = 0;
    var current: ?*const key.Key = k;

    while (current) |current_key| {
        if (current_key.parent) |_| {
            depth += 1;
            current = current_key.parent;
        } else {
            break;
        }
    }

    return depth;
}

/// Collect all values in a subtree
pub fn collectValues(root: *key.Key, allocator: std.mem.Allocator) ![]key.ValueInfo {
    var result = std.ArrayList(key.ValueInfo).init(allocator);
    var iter = TreeIterator.init(.DepthFirst, true);
    defer iter.deinit();

    try iter.start(root);

    while (iter.next()) |k| {
        const values = try k.enumerateValues(allocator);
        defer {
            for (values) |v| allocator.free(v.name);
            allocator.free(values);
        }
        try result.appendSlice(values);
    }

    return result.toOwnedSlice();
}
