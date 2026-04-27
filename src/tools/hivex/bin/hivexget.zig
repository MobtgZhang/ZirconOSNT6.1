//! hivexget - Get registry value from Windows Registry Hive
//! 
//! This tool retrieves values from Windows Registry hive files using
//! the libhivex library.

const std = @import("std");
const hivex = @import("hivex");
const c = @cImport(@cInclude("stdio.h"));

const Hive = hivex.hive.Hive;

pub fn main(init: std.process.Init) void {
    var iter = std.process.Args.Iterator.init(init.minimal.args);
    _ = iter.next(); // Skip program name
    
    const hive_path = iter.next() orelse {
        std.debug.print("Usage: hivexget <hive_file> <key_path> [value_name]\n", .{});
        return;
    };
    
    const key_path = iter.next() orelse {
        std.debug.print("Usage: hivexget <hive_file> <key_path> [value_name]\n", .{});
        return;
    };
    
    // Open hive file
    var h = Hive.open(hive_path, true) catch |e| {
        std.debug.print("Error opening hive file: {s}\n", .{@errorName(e)});
        return;
    };
    defer h.close();
    
    // Navigate to key
    const data = h.getData();
    const root_offset = h.getRootOffset();
    
    if (root_offset <= 0 or @as(usize, @intCast(root_offset)) >= data.len) {
        std.debug.print("Invalid root offset\n", .{});
        return;
    }
    
    var current_offset: i32 = root_offset;
    var it = std.mem.splitScalar(u8, key_path, '\\');
    
    while (it.next()) |component| {
        if (component.len == 0) continue;
        
        if (current_offset <= 0 or @as(usize, @intCast(current_offset)) >= data.len) {
            std.debug.print("Key not found: {s}\n", .{key_path});
            return;
        }
        
        const nk_data = data[@as(usize, @intCast(current_offset))..];
        const nk_cell = hivex.hive.NkCell.parse(nk_data) catch {
            std.debug.print("Failed to parse key\n", .{});
            return;
        };
        
        if (!nk_cell.hasStableSubkeys()) {
            std.debug.print("Key not found: {s}\n", .{key_path});
            return;
        }
        
        const lf_offset_abs = @as(i32, @intCast(@as(usize, @intCast(current_offset)) + @as(usize, @intCast(nk_cell.subkey_index_offset_stable))));
        if (lf_offset_abs <= 0 or @as(usize, @intCast(lf_offset_abs)) >= data.len) {
            std.debug.print("Key not found: {s}\n", .{key_path});
            return;
        }
        
        const lf_data = data[@as(usize, @intCast(lf_offset_abs))..];
        const lf_cell = hivex.hive.LfCell.parse(lf_data) catch {
            std.debug.print("Key not found: {s}\n", .{key_path});
            return;
        };
        
        var found = false;
        for (0..lf_cell.getEntryCount()) |idx| {
            const entry = lf_cell.getEntry(idx) orelse continue;
            const nk_offset_abs = @as(i32, @intCast(@as(usize, @intCast(lf_offset_abs)) + @as(usize, @intCast(entry.nk_offset))));
            if (nk_offset_abs <= 0 or @as(usize, @intCast(nk_offset_abs)) >= data.len) continue;
            
            const sub_nk_data = data[@as(usize, @intCast(nk_offset_abs))..];
            const sub_nk = hivex.hive.NkCell.parse(sub_nk_data) catch continue;
            
            var name_buf: [256]u8 = undefined;
            const name_len = utf16leToString(sub_nk.getName(), &name_buf);
            if (std.mem.eql(u8, name_buf[0..name_len], component)) {
                current_offset = nk_offset_abs;
                found = true;
                break;
            }
        }
        
        if (!found) {
            std.debug.print("Key not found: {s}\n", .{key_path});
            return;
        }
    }
    
    // Get key info and print
    if (current_offset <= 0 or @as(usize, @intCast(current_offset)) >= data.len) {
        return;
    }
    
    const nk_data = data[@as(usize, @intCast(current_offset))..];
    const nk_cell = hivex.hive.NkCell.parse(nk_data) catch {
        std.debug.print("Failed to parse key\n", .{});
        return;
    };
    
    std.debug.print("Key: ", .{});
    printKeyName(nk_cell);
    std.debug.print("\n", .{});
    
    if (nk_cell.hasValues()) {
        std.debug.print("(values not yet fully implemented)\n", .{});
    }
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

fn printKeyName(nk_cell: hivex.hive.NkCell) void {
    const name_utf16 = nk_cell.getName();
    var buf: [256]u8 = undefined;
    const len = utf16leToString(name_utf16, &buf);
    std.debug.print("{s}", .{buf[0..len]});
}
