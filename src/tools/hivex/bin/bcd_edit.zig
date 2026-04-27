//! BCD Edit Tool
//! 
//! Command-line tool for editing BCD entries.

const std = @import("std");
const hivex = @import("hivex");

const bcd = hivex.bcd;
const parser = hivex.bcd;

/// Command line arguments
pub const Args = struct {
    /// BCD file path
    file: []const u8,

    /// Operation to perform
    operation: Operation,

    /// Object GUID
    guid: ?[]const u8 = null,

    /// Element type
    element_type: ?u32 = null,

    /// Element value
    element_value: ?[]const u8 = null,

    /// Source GUID for copy
    src_guid: ?[]const u8 = null,

    /// Destination GUID for copy
    dst_guid: ?[]const u8 = null,

    /// Export/Import path
    path: ?[]const u8 = null,

    /// Backup path
    backup_path: ?[]const u8 = null,
};

/// Operations
pub const Operation = enum {
    /// Enumerate objects
    Enum,
    /// Create object
    Create,
    /// Delete object
    Delete,
    /// Set element
    Set,
    /// Get element
    Get,
    /// Copy object
    Copy,
    /// Export to JSON
    Export,
    /// Import from JSON
    Import,
    /// Backup store
    Backup,
    /// Restore store
    Restore,
};

/// Parse command line arguments
pub fn parseArgs(args: [][]const u8) !Args {
    var result = Args{
        .file = &.{},
        .operation = .Enum,
    };

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--file")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.file = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--create")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.operation = .Create;
            result.guid = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--delete")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.operation = .Delete;
            result.guid = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--set")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.operation = .Set;
            const parts = std.mem.split(u8, args[i + 1], "=");
            const type_str = parts.next() orelse "";
            result.element_type = try std.fmt.parseInt(u32, type_str, 0);
            result.element_value = parts.next();
            i += 1;
        } else if (std.mem.eql(u8, arg, "-g") or std.mem.eql(u8, arg, "--get")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.operation = .Get;
            result.element_type = try std.fmt.parseInt(u32, args[i + 1], 0);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--enum")) {
            result.operation = .Enum;
        } else if (std.mem.eql(u8, arg, "--copy")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.operation = .Copy;
            const parts = std.mem.split(u8, args[i + 1], "=");
            result.src_guid = parts.next();
            result.dst_guid = parts.next();
            i += 1;
        } else if (std.mem.eql(u8, arg, "--export")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.operation = .Export;
            result.path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--import")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.operation = .Import;
            result.path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--backup")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.operation = .Backup;
            result.backup_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--restore")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.operation = .Restore;
            result.backup_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return error.ShowHelp;
        }
    }

    if (result.file.len == 0) {
        return error.MissingFile;
    }

    return result;
}

/// Perform the edit operation
pub fn edit(args: *const Args) !void {
    var store = try bcd.Store.BcdStore.open(args.file);
    defer store.close();

    switch (args.operation) {
        .Enum => {
            try editEnum(&store);
        },
        .Create => {
            if (args.guid) |g| {
                const guid = try bcd.Object.GUID.parse(g);
                _ = try store.createObject(bcd.Object.ObjectType.OsLoader, guid);
            }
        },
        .Delete => {
            if (args.guid) |g| {
                const guid = try bcd.Object.GUID.parse(g);
                try store.deleteObject(&guid);
            }
        },
        .Set => {
            try editSet(&store, args);
        },
        .Get => {
            try editGet(&store, args);
        },
        .Copy => {
            try editCopy(&store, args);
        },
        .Export => {
            try editExport(&store, args);
        },
        .Import => {
            try editImport(&store, args);
        },
        .Backup => {
            if (args.backup_path) |bp| {
                try store.backup(bp);
            }
        },
        .Restore => {
            if (args.backup_path) |bp| {
                try store.restore(bp);
            }
        },
    }

    try store.save();
}

fn editEnum(store: *bcd.Store.BcdStore) !void {
    const writer = std.io.getStdOut().writer();
    try writer.print("Enumeration:\n", .{});

    for (store.objects.items) |obj| {
        const guid_str = try obj.id.format(std.heap.page_allocator);
        defer std.heap.page_allocator.free(guid_str);
        try writer.print("  {s} ({s})\n", .{ guid_str, obj.object_type.getName() });
    }
}

fn editSet(store: *bcd.Store.BcdStore, args: *const Args) !void {
    _ = store;
    _ = args;
}

fn editGet(store: *bcd.Store.BcdStore, args: *const Args) !void {
    _ = store;
    _ = args;
}

fn editCopy(store: *bcd.Store.BcdStore, args: *const Args) !void {
    _ = store;
    _ = args;
}

fn editExport(store: *bcd.Store.BcdStore, args: *const Args) !void {
    _ = store;
    _ = args;
}

fn editImport(store: *bcd.Store.BcdStore, args: *const Args) !void {
    _ = store;
    _ = args;
}

/// Show help message
pub fn showHelp() void {
    const help_text =
        \\Usage: bcd_edit [OPTIONS]
        \\
        \\Options:
        \\  -f, --file <path>       BCD file path
        \\  -c, --create <guid>     Create object with GUID
        \\  -d, --delete <guid>     Delete object by GUID
        \\  -s, --set <type>=<val>  Set element value
        \\  -g, --get <type>        Get element value
        \\  --enum                   Enumerate objects
        \\  --copy <src>=<dst>      Copy object
        \\  --export <path>          Export to JSON
        \\  --import <path>         Import from JSON
        \\  --backup <path>         Backup store
        \\  --restore <path>         Restore store
        \\  -h, --help              Show this help message
        \\
    ;
    std.io.getStdOut().writeAll(help_text) catch {};
}

/// Main entry point
pub fn main() void {
    std.debug.print("BCD Edit Tool - ZirconOS\n", .{});
    std.debug.print("Usage: bcd_edit <bcd_file>\n", .{});
}

/// Error types
pub const Error = error{
    MissingFile,
    MissingArgument,
    ShowHelp,
    InvalidArgs,
    IoError,
};
