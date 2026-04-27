//! hivexsh - Interactive shell for Windows Registry Hive files
//! 
//! This tool provides an interactive shell to navigate and query
//! Windows Registry hive files using the libhivex library.

const std = @import("std");
const hivex = @import("hivex");
const c = @cImport(@cInclude("stdio.h"));

const hive = hivex.hive;

var g_hive: ?hive.Hive = null;
var g_current_path: []u8 = &.{};
var g_allocator: std.mem.Allocator = undefined;

fn printUsage() void {
    std.debug.print("hivexsh [-dfwu] [hivefile]\n", .{});
    std.debug.print("  -d  Open hive file and print debug information\n", .{});
    std.debug.print("  -f  Open hive file in read-write mode (force)\n", .{});
    std.debug.print("  -w  Open hive file in read-write mode\n", .{});
    std.debug.print("  -u  Use unsafe operations (heuristics for corrupted hives)\n", .{});
}

fn utf16leToString(utf16: []const u16, buf: []u8) usize {
    var pos: usize = 0;
    
    for (utf16) |wc| {
        if (wc == 0) break;
        if (wc < 0x80) {
            if (pos < buf.len - 1) {
                buf[pos] = @as(u8, @truncate(wc));
                pos += 1;
            }
        } else if (wc < 0x800) {
            if (pos < buf.len - 2) {
                buf[pos] = @as(u8, @truncate(0xC0 | (wc >> 6)));
                buf[pos + 1] = @as(u8, @truncate(0x80 | (wc & 0x3F)));
                pos += 2;
            }
        } else {
            if (pos < buf.len - 3) {
                buf[pos] = @as(u8, @truncate(0xE0 | (wc >> 12)));
                buf[pos + 1] = @as(u8, @truncate(0x80 | ((wc >> 6) & 0x3F)));
                buf[pos + 2] = @as(u8, @truncate(0x80 | (wc & 0x3F)));
                pos += 3;
            }
        }
    }
    
    return pos;
}

fn openHive(path: []const u8, readonly: bool) !void {
    const hive_file = try hive.Hive.open(path, readonly);
    g_hive = hive_file;
    g_current_path = try g_allocator.dupe(u8, "\\");
    std.debug.print("hivex: hivex_open: created handle {*}\n", .{&g_hive});
}

fn closeHive() void {
    if (g_hive) |*h| {
        h.close();
        g_hive = null;
    }
}

fn getHive() !*hive.Hive {
    if (g_hive) |*h| {
        return h;
    }
    return error.NoHiveOpen;
}

fn printKeyName(nk_cell: hive.NkCell) void {
    const name_utf16 = nk_cell.getName();
    var buf: [256]u8 = undefined;
    const len = utf16leToString(name_utf16, &buf);
    std.debug.print("{s}", .{buf[0..len]});
}

fn listSubkeys(data: []const u8, nk_cell: hive.NkCell, root_offset: i32) void {
    if (!nk_cell.hasStableSubkeys()) {
        std.debug.print("(no subkeys)\n", .{});
        return;
    }
    
    const lf_offset_abs = @as(i32, @intCast(@as(usize, @intCast(root_offset)) + @as(usize, @intCast(nk_cell.subkey_index_offset_stable))));
    if (lf_offset_abs <= 0 or @as(usize, @intCast(lf_offset_abs)) >= data.len) {
        std.debug.print("(invalid subkey list offset)\n", .{});
        return;
    }
    
    const lf_data = data[@as(usize, @intCast(lf_offset_abs))..];
    const lf_cell = hive.LfCell.parse(lf_data) catch {
        std.debug.print("(failed to parse subkey list)\n", .{});
        return;
    };
    
    const count = lf_cell.getEntryCount();
    std.debug.print("Subkeys ({d}):\n", .{count});
    
    for (0..count) |i| {
        const entry = lf_cell.getEntry(i) orelse continue;
        const nk_offset_abs = @as(i32, @intCast(@as(usize, @intCast(lf_offset_abs)) + @as(usize, @intCast(entry.nk_offset))));
        if (nk_offset_abs <= 0 or @as(usize, @intCast(nk_offset_abs)) >= data.len) continue;
        
        const sub_nk_data = data[@as(usize, @intCast(nk_offset_abs))..];
        const sub_nk = hive.NkCell.parse(sub_nk_data) catch continue;
        
        std.debug.print("  ", .{});
        printKeyName(sub_nk);
        std.debug.print("\n", .{});
    }
}

fn listCurrentKey() !void {
    const h = try getHive();
    const data = h.getData();
    const root_offset = h.getRootOffset();
    
    if (root_offset <= 0 or @as(usize, @intCast(root_offset)) >= data.len) {
        std.debug.print("Error: Invalid root offset\n", .{});
        return;
    }
    
    const nk_data = data[@as(usize, @intCast(root_offset))..];
    const nk_cell = hive.NkCell.parse(nk_data) catch {
        std.debug.print("Error: Failed to parse root key\n", .{});
        return;
    };
    
    std.debug.print("Key name: ", .{});
    printKeyName(nk_cell);
    std.debug.print("\n", .{});
    
    const subkey_count = nk_cell.getSubkeyCount();
    std.debug.print("Number of subkeys: {d}\n", .{subkey_count});
    std.debug.print("Number of values: {d}\n", .{nk_cell.value_count});
    
    listSubkeys(data, nk_cell, root_offset);
}

fn navigateTo(path: []const u8) !void {
    if (g_current_path.len > 0 and g_current_path[0] != 0) {
        g_allocator.free(g_current_path);
    }
    g_current_path = try g_allocator.dupe(u8, path);
}

fn showCurrentPath() void {
    std.debug.print("{s}\n", .{g_current_path});
}

fn runInteractive() !void {
    var input_buf: [4096]u8 = undefined;
    
    std.debug.print("hivexsh> ", .{});
    
    while (true) {
        if (c.fgets(&input_buf, 4096, c.stdin)) |_| {
            // Remove trailing newline
            var len: usize = 0;
            while (len < input_buf.len and input_buf[len] != 0) : (len += 1) {}
            while (len > 0 and (input_buf[len - 1] == '\n' or input_buf[len - 1] == '\r')) {
                len -= 1;
            }
            
            if (len == 0) {
                std.debug.print("hivexsh> ", .{});
                continue;
            }
            
            const input = input_buf[0..len];
            
            var cmd_end: usize = 0;
            while (cmd_end < input.len and input[cmd_end] != ' ') : (cmd_end += 1) {}
            const cmd = input[0..cmd_end];
            
            if (std.mem.eql(u8, cmd, "exit") or std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "q")) {
                break;
            } else if (std.mem.eql(u8, cmd, "ls") or std.mem.eql(u8, cmd, "dir")) {
                listCurrentKey() catch {};
            } else if (std.mem.eql(u8, cmd, "pwd")) {
                showCurrentPath();
            } else if (std.mem.eql(u8, cmd, "cd")) {
                const rest = if (cmd_end < input.len) input[cmd_end + 1..] else "";
                if (rest.len > 0) {
                    navigateTo(rest) catch {};
                }
            } else if (std.mem.eql(u8, cmd, "help")) {
                std.debug.print("Commands:\n", .{});
                std.debug.print("  ls/dir    - List current key contents\n", .{});
                std.debug.print("  cd <path> - Change directory (key path)\n", .{});
                std.debug.print("  pwd       - Show current path\n", .{});
                std.debug.print("  exit/quit - Exit shell\n", .{});
            } else if (cmd.len > 0) {
                std.debug.print("Unknown command: {s}\n", .{cmd});
            }
        } else {
            break;
        }
        
        std.debug.print("hivexsh> ", .{});
    }
}

pub fn main(init: std.process.Init) void {
    g_allocator = init.gpa;
    
    var iter = std.process.Args.Iterator.init(init.minimal.args);
    _ = iter.next(); // Skip program name
    
    var hive_path: ?[:0]const u8 = null;
    var readonly = true;
    var debug_mode = false;
    
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-d")) {
            debug_mode = true;
        } else if (std.mem.eql(u8, arg, "-f")) {
            readonly = false;
        } else if (std.mem.eql(u8, arg, "-w")) {
            readonly = false;
        } else if (std.mem.eql(u8, arg, "-u")) {
            // ignore for now
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsage();
            return;
        } else if (arg.len > 0 and arg[0] != '-' and hive_path == null) {
            hive_path = arg;
        }
    }
    
    if (hive_path == null) {
        printUsage();
        return;
    }
    
    if (hive_path) |path| {
        openHive(path, readonly) catch |e| {
            std.debug.print("hivexsh: failed to open hive file: {s}: {s}\n", .{ path, @errorName(e) });
            return;
        };
    }
    
    if (debug_mode) {
        if (g_hive) |*h| {
            const hdr = h.getHeader();
            std.debug.print("Header signature: {x}\n", .{hdr.signature});
            std.debug.print("Version: {d}.{d}\n", .{hdr.major_version, hdr.minor_version});
            std.debug.print("Root cell offset: {d}\n", .{hdr.root_cell_offset});
        }
    }
    
    runInteractive() catch {};
    
    closeHive();
}
