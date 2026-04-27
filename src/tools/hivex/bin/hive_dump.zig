//! Hive Dump Tool
//! 
//! Dumps registry hive contents in readable format.

const std = @import("std");
const hivex = @import("hivex");

const hive = hivex.hive;
const nk = hivex.hive;
const vk = hivex.hive;

/// Command line arguments
pub const Args = struct {
    /// Hive file path
    file: []const u8,

    /// Output file path
    output: ?[]const u8 = null,

    /// Show raw format
    raw: bool = false,

    /// Show header only
    header_only: bool = false,

    /// Show cells
    show_cells: bool = false,

    /// Show key tree
    show_tree: bool = false,

    /// Show values
    show_values: bool = false,

    /// Show security
    show_security: bool = false,

    /// Verbose output
    verbose: bool = false,

    /// Verify checksum
    verify_checksum: bool = false,

    /// Hex output
    hex: bool = false,
};

/// Parse command line arguments
pub fn parseArgs(args: [][]const u8) !Args {
    var result = Args{
        .file = &.{},
    };

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--file")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.file = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.output = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--raw")) {
            result.raw = true;
        } else if (std.mem.eql(u8, arg, "--header")) {
            result.header_only = true;
        } else if (std.mem.eql(u8, arg, "--cells")) {
            result.show_cells = true;
        } else if (std.mem.eql(u8, arg, "--tree")) {
            result.show_tree = true;
        } else if (std.mem.eql(u8, arg, "--values")) {
            result.show_values = true;
        } else if (std.mem.eql(u8, arg, "--security")) {
            result.show_security = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            result.verbose = true;
        } else if (std.mem.eql(u8, arg, "--checksum")) {
            result.verify_checksum = true;
        } else if (std.mem.eql(u8, arg, "--hex")) {
            result.hex = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return error.ShowHelp;
        }
    }

    if (result.file.len == 0) {
        return error.MissingFile;
    }

    return result;
}

/// Dump the hive
pub fn dumpHive(args: *const Args) !void {
    const hive_store = try hive.Hive.open(args.file, true);
    defer hive_store.close();

    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    defer buf.deinit();
    const writer = buf.writer();

    try dumpHeader(&hive_store, writer);

    if (!args.header_only) {
        if (args.show_cells) {
            try dumpCells(&hive_store, writer);
        }
        if (args.show_tree) {
            try dumpKeyTree(&hive_store, writer);
        }
        if (args.show_values) {
            try dumpValues(&hive_store, writer);
        }
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

fn dumpHeader(store: *const hive.Hive, writer: anytype) !void {
    const hdr = store.getHeader();
    try writer.print("Hive Header\n", .{});
    try writer.print("==========\n", .{});
    try writer.print("Signature: {s}\n", .{&hdr.signature});
    try writer.print("Version: {d}.{d}\n", .{hdr.major_version, hdr.minor_version});
    try writer.print("Sequence: {d}\n", .{hdr.sequence_number});
    try writer.print("Root Offset: {d}\n", .{hdr.root_cell_offset});
    try writer.print("File Size: {d} bytes\n", .{hdr.file_size});
    try writer.print("Format: {s}\n", .{
        if (hdr.isLogicalHive()) "Logical Hive" else "Direct Memory Load"
    });
    try writer.print("\n", .{});
}

fn dumpCells(store: *const hive.Hive, writer: anytype) !void {
    const data = store.getData();
    try writer.print("Cells\n", .{});
    try writer.print("=====\n", .{});

    var iter = hive.HbinBlock.CellIterator.init(data, 4096);
    var count: usize = 0;

    while (iter.next()) |cell| {
        if (!cell.isAllocated()) continue;
        count += 1;
        if (count > 100) {
            try writer.print("... (truncated after 100 cells)\n", .{});
            break;
        }

        const sig = if (cell.data.len >= 2) cell.data[0..2] else &.{};
        const sig_str = std.fmt.bytesHexLower(sig);
        try writer.print("Offset {d}: size={d}, sig={s}\n", .{
            cell.offset, cell.size, sig_str
        });
    }
    try writer.print("\n", .{});
}

fn dumpKeyTree(store: *const hive.Hive, writer: anytype) !void {
    _ = store;
    _ = writer;
}

fn dumpValues(store: *const hive.Hive, writer: anytype) !void {
    _ = store;
    _ = writer;
}

/// Show help message
pub fn showHelp() void {
    const help_text =
        \\Usage: hive_dump [OPTIONS]
        \\
        \\Options:
        \\  -f, --file <path>       Hive file path
        \\  -o, --output <path>    Output file path
        \\  -r, --raw              Raw format output
        \\  --header               Show header only
        \\  --cells                Show cell information
        \\  --tree                 Show key tree
        \\  --values               Show values
        \\  --security             Show security descriptors
        \\  -v, --verbose          Verbose output
        \\  --checksum             Verify checksum
        \\  --hex                  Hex output
        \\  -h, --help             Show this help message
        \\
    ;
    std.io.getStdOut().writeAll(help_text) catch {};
}

/// Main entry point
pub fn main() void {
    std.debug.print("Hive Dump Tool - ZirconOS\n", .{});
    std.debug.print("Usage: hive_dump <hive_file>\n", .{});
}

/// Error types
pub const Error = error{
    MissingFile,
    MissingArgument,
    ShowHelp,
    InvalidArgs,
    IoError,
};
