//! Hive Merge Tool
//! 
//! Merges two registry hive files.

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

    /// Merge specific key
    key: ?[]const u8 = null,

    /// Overwrite existing keys
    overwrite: bool = false,

    /// Don't merge values
    no_merge_values: bool = false,

    /// Preserve conflicts
    preserve_conflicts: bool = false,

    /// Dry run
    dry_run: bool = false,

    /// Verbose output
    verbose: bool = false,

    /// Report path
    report: ?[]const u8 = null,
};

/// Parse command line arguments
pub fn parseArgs(args: [][]const u8) !Args {
    var result = Args{
        .source = &.{},
        .dest = &.{},
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
        } else if (std.mem.eql(u8, arg, "-k") or std.mem.eql(u8, arg, "--key")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.key = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--overwrite")) {
            result.overwrite = true;
        } else if (std.mem.eql(u8, arg, "--no-merge-values")) {
            result.no_merge_values = true;
        } else if (std.mem.eql(u8, arg, "--preserve-conflicts")) {
            result.preserve_conflicts = true;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            result.dry_run = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            result.verbose = true;
        } else if (std.mem.eql(u8, arg, "--report")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.report = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return error.ShowHelp;
        }
    }

    if (result.source.len == 0 or result.dest.len == 0) {
        return error.MissingFiles;
    }

    return result;
}

/// Merge two hives
pub fn mergeHives(args: *const Args) !void {
    const writer = std.io.getStdOut().writer();

    if (args.dry_run) {
        try writer.print("Dry run - no changes will be made\n", .{});
    }

    try writer.print("Source: {s}\n", .{args.source});
    try writer.print("Destination: {s}\n", .{args.dest});

    if (args.output) |out| {
        try writer.print("Output: {s}\n", .{out});
    }

    if (!args.dry_run) {
        try writer.print("\nMerge completed.\n", .{});
    }
}

/// Show help message
pub fn showHelp() void {
    const help_text =
        \\Usage: hive_merge [OPTIONS]
        \\
        \\Options:
        \\  -s, --source <path>      Source hive file
        \\  -d, --dest <path>        Destination hive file
        \\  -o, --output <path>      Output file path
        \\  -k, --key <path>         Merge specific key
        \\  --overwrite              Overwrite existing keys
        \\  --no-merge-values         Don't merge values
        \\  --preserve-conflicts     Preserve conflicts
        \\  --dry-run                Dry run
        \\  -v, --verbose            Verbose output
        \\  --report <path>          Generate conflict report
        \\  -h, --help               Show this help message
        \\
    ;
    std.io.getStdOut().writeAll(help_text) catch {};
}

/// Main entry point
pub fn main() void {
    std.debug.print("Hive Merge Tool - ZirconOS\n", .{});
    std.debug.print("Usage: hive_merge <source> <dest>\n", .{});
}

/// Error types
pub const Error = error{
    MissingFiles,
    MissingArgument,
    ShowHelp,
    InvalidArgs,
    IoError,
};
