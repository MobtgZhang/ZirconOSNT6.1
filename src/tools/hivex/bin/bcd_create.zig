//! BCD Create Tool
//! 
//! Creates a new BCD store from template.

const std = @import("std");
const hivex = @import("hivex");

const bcd = hivex.bcd;

/// Command line arguments
pub const Args = struct {
    /// Output file path
    output: []const u8,

    /// Template type
    template: TemplateType,

    /// JSON config path
    json: ?[]const u8 = null,

    /// Kernel path
    kernel: ?[]const u8 = null,

    /// Initrd path
    initrd: ?[]const u8 = null,

    /// Boot device
    boot_device: ?[]const u8 = null,

    /// Boot loader path
    boot_loader: ?[]const u8 = null,

    /// Timeout in seconds
    timeout: ?u32 = null,

    /// Quiet mode
    quiet: bool = false,
};

/// Template type
pub const TemplateType = enum {
    /// Windows template
    Windows,
    /// Recovery template
    Recovery,
    /// ZirconOS template
    ZirconOs,
};

/// Parse command line arguments
pub fn parseArgs(args: [][]const u8) !Args {
    var result = Args{
        .output = &.{},
        .template = .Windows,
    };

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--template")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.template = switch (args[i + 1][0]) {
                'w', 'W' => .Windows,
                'r', 'R' => .Recovery,
                'z', 'Z' => .ZirconOs,
                else => .Windows,
            };
            i += 1;
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.output = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "-j") or std.mem.eql(u8, arg, "--json")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.json = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--windows")) {
            result.template = .Windows;
        } else if (std.mem.eql(u8, arg, "--recovery")) {
            result.template = .Recovery;
        } else if (std.mem.eql(u8, arg, "--zirconos")) {
            result.template = .ZirconOs;
        } else if (std.mem.eql(u8, arg, "--with-kernel")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.kernel = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--with-initrd")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.initrd = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--boot-device")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.boot_device = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--boot-loader")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.boot_loader = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--timeout")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            result.timeout = try std.fmt.parseInt(u32, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--quiet") or std.mem.eql(u8, arg, "-q")) {
            result.quiet = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return error.ShowHelp;
        }
    }

    if (result.output.len == 0) {
        return error.MissingOutput;
    }

    return result;
}

/// Create BCD store from template
pub fn createFromTemplate(args: *const Args) !void {
    const template_type: bcd.Store.TemplateType = switch (args.template) {
        .Windows => .Windows,
        .Recovery => .Recovery,
        .ZirconOs => .ZirconOs,
    };

    var store = try bcd.Store.BcdStore.create(args.output, template_type);
    defer store.close();

    if (!args.quiet) {
        try std.io.getStdOut().writer().print("Created BCD store: {s}\n", .{args.output});
        try std.io.getStdOut().writer().print("Template: {s}\n", .{@tagName(args.template)});
    }

    try store.save();
}

/// Show help message
pub fn showHelp() void {
    const help_text =
        \\Usage: bcd_create [OPTIONS]
        \\
        \\Options:
        \\  -t, --template <name>    Template name (windows, recovery, zirconos)
        \\  -o, --output <path>      Output file path
        \\  -j, --json <path>        JSON configuration file
        \\  --windows                 Windows template
        \\  --recovery               Recovery template
        \\  --zirconos              ZirconOS template
        \\  --with-kernel <path>     Kernel path
        \\  --with-initrd <path>     Initrd path
        \\  --boot-device <path>      Boot device
        \\  --boot-loader <path>     Boot loader path
        \\  --timeout <seconds>      Boot timeout
        \\  -q, --quiet              Quiet mode
        \\  -h, --help               Show this help message
        \\
    ;
    std.io.getStdOut().writeAll(help_text) catch {};
}

/// Main entry point
pub fn main() void {
    std.debug.print("BCD Create Tool - ZirconOS\n", .{});
    std.debug.print("Usage: bcd_create <output_file>\n", .{});
}

/// Error types
pub const Error = error{
    MissingOutput,
    MissingArgument,
    ShowHelp,
    InvalidArgs,
    IoError,
};
