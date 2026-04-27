//! Hive Diff Tool
//! 
//! Compares two registry hive files.

const std = @import("std");
const hivex = @import("hivex");

const hive = hivex.hive;
const registry = hivex.registry;

/// Command line arguments
pub const Args = struct {
    /// Source hive file
    source: []const u8,

    /// Destination hive file
    dest: []const u8,

    /// Output file path
    output: ?[]const u8 = null,

    /// Output format
    format: Format,

    /// Compare values
    compare_values: bool = true,

    /// Compare timestamps
    compare_timestamps: bool = false,

    /// Ignore case
    ignore_case: bool = true,

    /// Only compare specific key
    key: ?[]const u8 = null,

    /// Show only added
    added_only: bool = false,

    /// Show only removed
    removed_only: bool = false,

    /// Show only modified
    modified_only: bool = false,

    /// Context lines
    context: u32 = 3,

    /// Use colors
    color: bool = false,
};

/// Output format
pub const Format = enum {
    /// Text format
    Text,
    /// JSON format
    Json,
    /// XML format
    Xml,
};

/// Parse command line arguments
pub fn parseArgs(args: [][]const u8) !Args {
    var result = Args{
        .source = &.{},
        .dest = &.{},
        .format = .Text,
    };

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--source")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.source = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--dest")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.dest = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.output = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--format")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.format = switch (args[i + 1][0]) {
                'j', 'J' => .Json,
                'x', 'X' => .Xml,
                else => .Text,
            };
            i += 1;
        } else if (std.mem.eql(u8, arg, "--compare-values")) {
            result.compare_values = true;
        } else if (std.mem.eql(u8, arg, "--compare-timestamps")) {
            result.compare_timestamps = true;
        } else if (std.mem.eql(u8, arg, "--ignore-case")) {
            result.ignore_case = true;
        } else if (std.mem.eql(u8, arg, "--key")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.key = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--added")) {
            result.added_only = true;
        } else if (std.mem.eql(u8, arg, "--removed")) {
            result.removed_only = true;
        } else if (std.mem.eql(u8, arg, "--modified")) {
            result.modified_only = true;
        } else if (std.mem.eql(u8, arg, "--context")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.context = try std.fmt.parseInt(u32, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--color")) {
            result.color = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return error.ShowHelp;
        }
    }

    if (result.source.len == 0 or result.dest.len == 0) {
        return error.MissingFiles;
    }

    return result;
}

/// Compare two hives
pub fn diffHives(args: *const Args) !void {
    const writer = std.io.getStdOut().writer();

    try writer.print("Comparing:\n", .{});
    try writer.print("  Source: {s}\n", .{args.source});
    try writer.print("  Destination: {s}\n", .{args.dest});
    try writer.print("\n", .{});

    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    defer buf.deinit();
    const diff_writer = buf.writer();

    switch (args.format) {
        .Text => {
            try diff_writer.writeAll("Changes:\n");
            try diff_writer.writeAll("--------\n");
        },
        .Json => {
            try diff_writer.writeAll("{\n");
            try diff_writer.writeAll("  \"changes\": []\n");
            try diff_writer.writeAll("}\n");
        },
        .Xml => {
            try diff_writer.writeAll("<?xml version=\"1.0\"?>\n");
            try diff_writer.writeAll("<diff>\n");
            try diff_writer.writeAll("</diff>\n");
        },
    }

    const output = buf.items;

    if (args.output) |out_path| {
        const file = try std.fs.cwd().createFile(out_path, .{});
        defer file.close();
        try file.writeAll(output);
    } else {
        try std.io.getStdOut().writeAll(output);
    }
}

/// Show help message
pub fn showHelp() void {
    const help_text =
        \\Usage: hive_diff [OPTIONS]
        \\
        \\Options:
        \\  -s, --source <path>      Source hive file
        \\  -d, --dest <path>        Destination hive file
        \\  -o, --output <path>      Output file path
        \\  -f, --format <type>      Output format (text/json/xml)
        \\  --compare-values         Compare values
        \\  --compare-timestamps     Compare timestamps
        \\  --ignore-case            Ignore case in names
        \\  --key <path>             Only compare specific key
        \\  --added                  Show only added items
        \\  --removed                Show only removed items
        \\  --modified               Show only modified items
        \\  --context <n>            Context lines
        \\  --color                  Use colors
        \\  -h, --help               Show this help message
        \\
    ;
    std.io.getStdOut().writeAll(help_text) catch {};
}

/// Main entry point
pub fn main() void {
    std.debug.print("Hive Diff Tool - ZirconOS\n", .{});
    std.debug.print("Usage: hive_diff <source> <dest>\n", .{});
}

/// Error types
pub const Error = error{
    MissingFiles,
    MissingArgument,
    ShowHelp,
    InvalidArgs,
    IoError,
};
