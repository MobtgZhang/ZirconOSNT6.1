//! hivexregedit - Windows Registry Hive Editor
//!
//! This tool can export and merge Windows Registry hive files in the
//! regedit text format. This is a pure Zig reimplementation that produces
//! output identical to the system hivexregedit command.

const std = @import("std");
const hivex = @import("hivex");
const hive = hivex.hive;

const gpa = std.heap.page_allocator;

/// Write output to stdout using write syscall
fn writeStdout(buf: []const u8) void {
    const libc = @cImport(@cInclude("unistd.h"));
    _ = libc.write(1, buf.ptr, buf.len);
}

/// Print formatted output to stdout
fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [16384]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, fmt, args) catch return;
    writeStdout(result);
}

/// Initialize an ArrayList(u8) with capacity
fn initByteList(capacity: usize) std.ArrayList(u8) {
    return std.ArrayList(u8).initCapacity(gpa, capacity) catch return std.ArrayList(u8).empty;
}

/// Initialize an ArrayList(usize) with capacity
fn initUsizeList(capacity: usize) std.ArrayList(usize) {
    return std.ArrayList(usize).initCapacity(gpa, capacity) catch return std.ArrayList(usize).empty;
}

/// Initialize an ArrayList(T) with capacity
fn initList(comptime T: type, capacity: usize) std.ArrayList(T) {
    return std.ArrayList(T).initCapacity(gpa, capacity) catch return std.ArrayList(T).empty;
}

/// Append a byte to an ArrayList(u8)
fn listAppendByte(list: *std.ArrayList(u8), b: u8) void {
    list.append(gpa, b) catch {};
}

/// Append a byte slice to an ArrayList(u8)
fn listAppendSlice(list: *std.ArrayList(u8), data: []const u8) void {
    list.appendSlice(gpa, data) catch {};
}

/// Append a single hex byte (e.g. "f") to an ArrayList(u8)
fn listAppendHexByte(list: *std.ArrayList(u8), b: u8) void {
    const hex = std.fmt.bytesToHex([1]u8{b}, .lower);
    listAppendSlice(list, &hex);
}

/// Escape backslashes and double-quotes in registry value names, appending to out
fn escapeAndAppendValueName(out: *std.ArrayList(u8), name: []const u8) void {
    for (name) |c| {
        if (c == '\\') {
            listAppendSlice(out, "\\\\");
        } else if (c == '"') {
            listAppendSlice(out, "\\\"");
        } else if (c == '\n') {
            listAppendSlice(out, "\\n");
        } else if (c == '\r') {
            listAppendSlice(out, "\\r");
        } else {
            listAppendByte(out, c);
        }
    }
}

/// Append a hex dump of data to out
fn appendHexDump(out: *std.ArrayList(u8), data: []const u8) void {
    var first = true;
    for (data) |b| {
        if (!first) {
            listAppendByte(out, ',');
        }
        first = false;
        listAppendHexByte(out, b);
    }
}

/// Append a DWORD value to out (e.g. "dword:0000000a")
fn appendDword(out: *std.ArrayList(u8), val: u32) void {
    listAppendSlice(out, "dword:");
    var buf: [8]u8 = undefined;
    const hex_str = std.fmt.bufPrint(&buf, "{x:0>8}", .{val}) catch "00000000";
    listAppendSlice(out, hex_str);
}

/// Append a value type label to out (e.g. "hex(7):" or "hex(2):")
fn appendValueType(out: *std.ArrayList(u8), t: u32) void {
    listAppendSlice(out, "hex(");
    var buf: [16]u8 = undefined;
    const hex_str = std.fmt.bufPrint(&buf, "{x}", .{t}) catch "0";
    listAppendSlice(out, hex_str);
    listAppendByte(out, ')');
    listAppendByte(out, ':');
}

/// Convert UTF-16LE bytes to UTF-8 string
fn utf16leToUtf8(data: []const u8) []u8 {
    var result = std.ArrayList(u8).initCapacity(gpa, data.len) catch return &.{};

    var i: usize = 0;
    while (i + 1 < data.len) : (i += 2) {
        const char = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(data[i..i+2].ptr)), .little);
        if (char == 0) break;

        if (char < 0x80) {
            result.append(gpa, @as(u8, @intCast(char))) catch break;
        } else if (char < 0x800) {
            result.append(gpa, @as(u8, @intCast(0xC0 | (char >> 6)))) catch break;
            result.append(gpa, @as(u8, @intCast(0x80 | (char & 0x3F)))) catch break;
        } else {
            result.append(gpa, @as(u8, @intCast(0xE0 | (char >> 12)))) catch break;
            result.append(gpa, @as(u8, @intCast(0x80 | ((char >> 6) & 0x3F)))) catch break;
            result.append(gpa, @as(u8, @intCast(0x80 | (char & 0x3F)))) catch break;
        }
    }

    const slice = result.toOwnedSlice(gpa) catch return &.{};
    result.deinit(gpa);
    return slice;
}

/// Read a signed 32-bit integer from little-endian bytes
fn readI32(data: []const u8, offset: usize) i32 {
    return std.mem.readInt(i32, @as(*const [4]u8, @ptrCast(data[offset..offset+4].ptr)), .little);
}

/// Read an unsigned 32-bit integer from little-endian bytes
fn readU32(data: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, @as(*const [4]u8, @ptrCast(data[offset..offset+4].ptr)), .little);
}

/// Read an unsigned 16-bit integer from little-endian bytes
fn readU16(data: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(data[offset..offset+2].ptr)), .little);
}

/// Check if a block at offset is valid
fn isValidBlock(data: []const u8, offset: usize) bool {
    if (offset < 0x1000 or offset >= data.len or (offset & 3) != 0) {
        return false;
    }
    return true;
}

/// Get block length from hbin block header
fn getBlockLen(data: []const u8, offset: usize) ?usize {
    if (offset < 4 or offset >= data.len) return null;
    const len = std.mem.readInt(i32, @as(*const [4]u8, @ptrCast(data[offset-4..offset].ptr)), .little);
    if (len >= 0) return null;
    const abs_len: usize = @intCast(-@as(i64, @intCast(len)));
    return abs_len;
}

/// Check if a block ID matches expected
fn blockIdMatches(data: []const u8, offset: usize, id0: u8, id1: u8) bool {
    if (!isValidBlock(data, offset)) return false;
    if (offset + 2 > data.len) return false;
    return data[offset] == id0 and data[offset + 1] == id1;
}

/// Get subkey list offset from NK record (NK offset is at seg_len position)
/// NK record structure (from hivex-internal.h):
///   offset 0: seg_len
///   offset 4: "nk" signature
///   offset 6: flags (2 bytes)
///   offset 8: timestamp (8 bytes)
///   offset 16: unknown1 (4 bytes)
///   offset 20: parent (4 bytes)
///   offset 24: nr_subkeys (4 bytes)
///   offset 28: nr_subkeys_volatile (4 bytes)
///   offset 32: subkey_lf (4 bytes) - stable subkey list offset
///   offset 36: subkey_lf_volatile (4 bytes)
///   offset 40: nr_values (4 bytes)
///   offset 44: vallist (4 bytes)
fn getSubkeyListOffset(data: []const u8, nk_offset: usize) ?usize {
    // subkey_lf is at nk_offset + 32
    if (nk_offset + 36 > data.len) return null;
    const sk_off = readI32(data, nk_offset + 32);
    if (sk_off <= 0) return null;
    const abs_off: usize = @intCast(@as(i64, @intCast(sk_off)) + 0x1000);
    if (!isValidBlock(data, abs_off)) return null;
    return abs_off;
}

/// Get volatile subkey list offset from NK record
fn getVolatileSubkeyListOffset(data: []const u8, nk_offset: usize) ?usize {
    // subkey_lf_volatile is at nk_offset + 36
    if (nk_offset + 40 > data.len) return null;
    const sk_off = readI32(data, nk_offset + 36);
    if (sk_off <= 0) return null;
    const abs_off: usize = @intCast(@as(i64, @intCast(sk_off)) + 0x1000);
    if (!isValidBlock(data, abs_off)) return null;
    return abs_off;
}

/// Get number of subkeys (stable) from NK record
fn getSubkeyCount(data: []const u8, nk_offset: usize) u32 {
    // nr_subkeys is at nk_offset + 24
    if (nk_offset + 28 > data.len) return 0;
    return readU32(data, nk_offset + 24);
}

/// Get number of values from NK record (NK offset is at seg_len position)
fn getValueCount(data: []const u8, nk_offset: usize) u32 {
    // nr_values is at nk_offset + 40
    if (nk_offset + 44 > data.len) return 0;
    return readU32(data, nk_offset + 40);
}

/// Get value list offset from NK record
fn getValueListOffset(data: []const u8, nk_offset: usize) ?usize {
    // vallist is at nk_offset + 44
    if (nk_offset + 48 > data.len) return null;
    const vl_off = readI32(data, nk_offset + 44);
    if (vl_off <= 0) return null;
    const abs_off: usize = @intCast(@as(i64, @intCast(vl_off)) + 0x1000);
    if (!isValidBlock(data, abs_off)) return null;
    return abs_off;
}

/// Export a single value (VK record) to the output buffer
/// VK offset is at seg_len position
/// VK structure from hivex-internal.h:
///   offset 0: seg_len
///   offset 4: "vk" signature
///   offset 6: name_len (uint16)
///   offset 8: data_len (uint32)
///   offset 12: data_offset (uint32)
///   offset 16: data_type (uint32)
///   offset 20: flags (uint16)
///   offset 22: unknown2 (uint16)
///   offset 24+: name (variable)
fn exportValue(data: []const u8, vk_offset: usize, out: *std.ArrayList(u8)) void {
    if (vk_offset + 28 > data.len) return;

    // VK fields at "vk" position (vk_offset + 4)
    const vk_id = vk_offset + 4;
    const name_len = readU16(data, vk_id + 2);
    const data_len_raw = readU32(data, vk_id + 4);
    const data_off_raw = readU32(data, vk_id + 8);
    const val_type = readU32(data, vk_id + 12);
    const flags = readU16(data, vk_id + 16);

    // Name starts at vk_id + 20 = vk_offset + 24
    // Note: BCD format may differ from hivex-internal.h
    const name_start = vk_id + 20;
    var name_bytes: []const u8 = &.{};
    if (name_len > 0 and name_start + name_len <= data.len) {
        name_bytes = data[name_start..name_start + name_len];
    }

    const inline_bit: u32 = 0x80000000;
    const is_inline = (data_len_raw & inline_bit) != 0;
    const data_len: u32 = data_len_raw & ~inline_bit;

    var value_data: []const u8 = &.{};
    if (is_inline) {
        // Inline data is stored at the data_offset field position (vk_id + 8)
        if (vk_id + 8 + 4 <= data.len) {
            value_data = data[vk_id + 8..vk_id + 8 + @min(data_len, 4)];
        }
    } else {
        if (data_off_raw != 0) {
            var abs_data_off: usize = @intCast(@as(i64, @intCast(data_off_raw)) + 0x1000);
            var skip_header = false;
            
            // Check if first 4 bytes are seg_len (negative value indicating used block)
            // If so, skip the header and use VK's data_len
            if (abs_data_off + 4 <= data.len) {
                const possible_seg_len = readI32(data, abs_data_off);
                if (possible_seg_len < 0) {
                    skip_header = true;
                }
            }
            
            if (skip_header) {
                abs_data_off += 4;
            }
            
            if (abs_data_off + data_len <= data.len) {
                value_data = data[abs_data_off..abs_data_off + data_len];
            }
        }
    }

    const is_ascii_name = (flags & 0x0001) != 0;
    const is_default = (name_len == 0);

    if (is_default) {
        listAppendByte(out, '@');
    } else {
        listAppendByte(out, '"');
        if (is_ascii_name) {
            escapeAndAppendValueName(out, name_bytes);
        } else {
            const utf8_name = utf16leToUtf8(name_bytes);
            escapeAndAppendValueName(out, utf8_name);
            gpa.free(utf8_name);
        }
        listAppendByte(out, '"');
    }

    listAppendByte(out, '=');

    // REG_DWORD (type 4) with exactly 4 bytes of data -> special format
    // Both inline and non-inline DWORDs are supported
    if (val_type == 4 and data_len == 4 and value_data.len >= 4) {
        const dword = std.mem.readInt(u32, @as(*const [4]u8, @ptrCast(value_data.ptr)), .little);
        appendDword(out, dword);
        listAppendByte(out, '\n');
        return;
    }

    // All other types -> hex(type):XX,XX,...
    appendValueType(out, val_type);
    appendHexDump(out, value_data);
    listAppendByte(out, '\n');
}

/// Export all values for a key (NK record) to the output buffer
fn exportValues(data: []const u8, nk_offset: usize, out: *std.ArrayList(u8)) void {
    const val_count = getValueCount(data, nk_offset);
    if (val_count == 0) return;

    const vl_offset = getValueListOffset(data, nk_offset) orelse return;
    if (vl_offset + 4 > data.len) return;

    var i: u32 = 0;
    while (i < val_count) : (i += 1) {
        // Value list offset array starts at vl_offset + 4 (after seg_len)
        const entry_off = vl_offset + 4 + @as(usize, @intCast(i)) * 4;
        if (entry_off + 4 > data.len) break;

        const vk_off_raw = readU32(data, entry_off);
        const vk_abs_off: usize = @intCast(@as(i64, @intCast(vk_off_raw)) + 0x1000);

        // VK record: seg_len at vk_abs_off, "vk" at vk_abs_off + 4
        if (vk_abs_off + 8 <= data.len) {
            if (data[vk_abs_off + 4] == 'v' and data[vk_abs_off + 5] == 'k') {
                exportValue(data, vk_abs_off, out);
            }
        }
    }
}

/// Get subkey entries from LF/LH/RI/LI block, appending NK offsets to out
/// LF/LH record structure:
///   offset 0-1: id (2 bytes) - "lf" or "lh"
///   offset 2-3: nr_keys (2 bytes)
///   offset 4+: keys array, each entry is 8 bytes:
///     - offset 0-3: offset to nk record (4 bytes)
///     - offset 4-7: hash (4 bytes)
/// RI/LI record structure:
///   offset 0-1: id (2 bytes) - "ri" or "li"
///   offset 2-3: nr_offsets (2 bytes)
///   offset 4+: offset array, each entry is 4 bytes pointing directly to nk records
fn getSubkeyOffsets(data: []const u8, sk_offset: usize, out: *std.ArrayList(usize)) void {
    if (sk_offset + 8 > data.len) return;

    // Check for seg_len header first (lf/lh records start with seg_len)
    // The "lf" or "lh" ID is at offset + 4
    const id0 = data[sk_offset + 4];
    const id1 = data[sk_offset + 5];

    if (id0 == 'l' and (id1 == 'f' or id1 == 'h')) {
        // lf/lh record - keys array starts at offset 8, each key is 8 bytes
        // Note: seg_len is at sk_offset, "lf"/"lh" at sk_offset + 4
        const count = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(data[sk_offset+6..sk_offset+8].ptr)), .little);

        var i: u16 = 0;
        while (i < count) : (i += 1) {
            // keys[i] starts at sk_offset + 8 + i * 8
            // keys[i].offset is at sk_offset + 8 + i * 8 (first 4 bytes)
            const entry_off = sk_offset + 8 + @as(usize, @intCast(i)) * 8;
            if (entry_off + 4 > data.len) break;
            const nk_off_raw = readI32(data, entry_off);
            const nk_abs_off: usize = @intCast(@as(i64, @intCast(nk_off_raw)) + 0x1000);
            // NK record: seg_len at nk_abs_off, "nk" at nk_abs_off + 4
            if (nk_abs_off + 8 <= data.len) {
                if (data[nk_abs_off + 4] == 'n' and data[nk_abs_off + 5] == 'k') {
                    out.append(gpa, nk_abs_off) catch {};
                }
            }
        }
    } else if (id0 == 'r' and id1 == 'i') {
        // ri record - offsets array starts at offset 8
        // ri records point to other index records (lf/lh/li/ri)
        const count = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(data[sk_offset+6..sk_offset+8].ptr)), .little);
        var i: u16 = 0;
        while (i < count) : (i += 1) {
            const entry_off = sk_offset + 8 + @as(usize, @intCast(i)) * 4;
            if (entry_off + 4 > data.len) break;
            const sub_off_raw = readI32(data, entry_off);
            const sub_abs_off: usize = @intCast(@as(i64, @intCast(sub_off_raw)) + 0x1000);
            getSubkeyOffsets(data, sub_abs_off, out);
        }
    } else if (id0 == 'l' and id1 == 'i') {
        // li record - same format as ri, but points directly to NK records
        const count = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(data[sk_offset+6..sk_offset+8].ptr)), .little);
        var i: u16 = 0;
        while (i < count) : (i += 1) {
            const entry_off = sk_offset + 8 + @as(usize, @intCast(i)) * 4;
            if (entry_off + 4 > data.len) break;
            const nk_off_raw = readI32(data, entry_off);
            const nk_abs_off: usize = @intCast(@as(i64, @intCast(nk_off_raw)) + 0x1000);
            // NK record: "nk" at nk_abs_off + 4
            if (nk_abs_off + 8 <= data.len) {
                if (data[nk_abs_off + 4] == 'n' and data[nk_abs_off + 5] == 'k') {
                    out.append(gpa, nk_abs_off) catch {};
                }
            }
        }
    }
}

/// Get key name from NK record. Always returns a heap-allocated string that caller must free.
/// nk_offset is at seg_len position
/// NK fields from hivex-internal.h (relative to "nk" position):
///   offset 72: name_len (uint16le)
///   offset 74: classname_len (uint16le)
///   offset 76: name (inline)
fn getKeyName(data: []const u8, nk_offset: usize) []const u8 {
    // nk_id is the "nk" position (nk_offset + 4)
    const nk_id = nk_offset + 4;

    // name_len at nk_id + 72 = nk_offset + 76
    // name at nk_id + 76 = nk_offset + 80
    if (nk_id + 80 > data.len) return &.{};
    const name_len = readU16(data, nk_id + 72);
    const name_start = nk_id + 76;

    if (name_start + name_len > data.len) return &.{};

    const flags = readU16(data, nk_id + 2);
    const is_ascii = (flags & 0x0020) != 0;

    if (is_ascii) {
        // Return a copy of the ASCII name
        const copy = gpa.alloc(u8, name_len) catch return &.{};
        @memcpy(copy, data[name_start..name_start + name_len]);
        return copy;
    } else {
        return utf16leToUtf8(data[name_start..name_start + name_len]);
    }
}

/// Free a key name (always heap-allocated)
fn freeKeyName(name: []const u8) void {
    if (name.len > 0) {
        gpa.free(name);
    }
}

/// Export a list of subkeys recursively (handles sorting and recursion)
/// first_is_root indicates if the first key should be treated as the root key
fn exportSubkeysRecursively(data: []const u8, subkeys: []usize, path: *std.ArrayList(u8), out: *std.ArrayList(u8), first_is_root: bool) void {
    // Build a list of (name, offset) pairs for sorting
    var entries = initList(struct { name: []const u8, offset: usize }, subkeys.len);
    defer {
        for (entries.items) |e| {
            freeKeyName(e.name);
        }
        entries.deinit(gpa);
    }

    for (subkeys) |sub_off| {
        const name = getKeyName(data, sub_off);
        entries.append(gpa, .{ .name = name, .offset = sub_off }) catch {
            freeKeyName(name);
        };
    }

    // Bubble sort by name (case-insensitive)
    var i: usize = 0;
    while (i < entries.items.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < entries.items.len) : (j += 1) {
            const name_a = entries.items[i].name;
            const name_b = entries.items[j].name;
            const min_len = @min(name_a.len, name_b.len);
            var k: usize = 0;
            var swap_needed = false;
            while (k < min_len) {
                const ca = std.ascii.toLower(name_a[k]);
                const cb = std.ascii.toLower(name_b[k]);
                if (ca < cb) {
                    swap_needed = false;
                    break;
                } else if (ca > cb) {
                    swap_needed = true;
                    break;
                }
                k += 1;
            }
            if (k == min_len and name_a.len != name_b.len) {
                swap_needed = name_a.len > name_b.len;
            }
            if (swap_needed) {
                const tmp = entries.items[i];
                entries.items[i] = entries.items[j];
                entries.items[j] = tmp;
            }
        }
    }

    for (entries.items) |e| {
        const is_root = (first_is_root and entries.items[0].offset == e.offset);
        exportKeyRecursive(data, e.offset, path, out, is_root);
    }
}

/// Export a registry key (NK record) and all its children recursively
/// nk_offset is at seg_len position
/// is_root indicates if this is the root key (should not print key name in path)
fn exportKeyRecursive(data: []const u8, nk_offset: usize, path: *std.ArrayList(u8), out: *std.ArrayList(u8), is_root: bool) void {
    const key_name = getKeyName(data, nk_offset);
    defer freeKeyName(key_name);

    const old_len = path.items.len;
    if (!is_root and key_name.len > 0) {
        // Add backslash before subkey name
        listAppendByte(path, '\\');
        listAppendSlice(path, key_name);
    }

    // Print [path]
    listAppendByte(out, '[');
    if (path.items.len == 0) {
        // Root key - output single backslash
        listAppendByte(out, '\\');
    } else {
        listAppendSlice(out, path.items);
    }
    listAppendSlice(out, "]\n");

    exportValues(data, nk_offset, out);
    listAppendByte(out, '\n');

    // Export subkeys
    var subkeys = initUsizeList(256);
    defer subkeys.deinit(gpa);

    // Try stable subkeys first
    const sk_offset = getSubkeyListOffset(data, nk_offset);
    if (sk_offset) |off| {
        getSubkeyOffsets(data, off, &subkeys);
    }

    // Try volatile subkeys if no stable subkeys found
    if (subkeys.items.len == 0) {
        const vol_sk_offset = getVolatileSubkeyListOffset(data, nk_offset);
        if (vol_sk_offset) |off| {
            getSubkeyOffsets(data, off, &subkeys);
        }
    }

    if (subkeys.items.len > 0) {
        exportSubkeysRecursively(data, subkeys.items, path, out, false);
    }

    path.shrinkRetainingCapacity(old_len);
}

/// Find a child key by name (case-insensitive)
fn findChildKey(data: []const u8, nk_offset: usize, name: []const u8) ?usize {
    const subkey_count = getSubkeyCount(data, nk_offset);
    if (subkey_count == 0) return null;

    const sk_offset = getSubkeyListOffset(data, nk_offset) orelse return null;

    var subkeys = initUsizeList(@as(usize, @intCast(subkey_count)));
    defer subkeys.deinit(gpa);

    getSubkeyOffsets(data, sk_offset, &subkeys);

    for (subkeys.items) |sub_off| {
        const key_name = getKeyName(data, sub_off);
        const flags = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(data[sub_off+2..sub_off+4].ptr)), .little);
        const key_name_is_heap = (flags & 0x0020) == 0 and key_name.len > 0;
        const match = std.ascii.eqlIgnoreCase(key_name, name);
        if (key_name_is_heap) {
            freeKeyName(key_name);
        }
        if (match) {
            return sub_off;
        }
    }

    return null;
}

/// Resolve a path string to an NK offset (seg_len position)
/// root_offset should be at seg_len position (as used by hivex)
/// The function verifies the NK signature at root_offset + 4
fn resolvePath(data: []const u8, root_offset: usize, path: []const u8) ?usize {
    // Verify the NK signature is at root_offset + 4
    if (!isValidBlock(data, root_offset + 4)) return null;
    if (!blockIdMatches(data, root_offset + 4, 'n', 'k')) return null;

    if (path.len == 0 or std.mem.eql(u8, path, "\\")) {
        return root_offset;
    }

    var current = root_offset;
    var remaining = path;

    if (remaining.len > 0 and remaining[0] == '\\') {
        remaining = remaining[1..];
    }

    while (remaining.len > 0) {
        const sep = std.mem.indexOfScalar(u8, remaining, '\\');
        const component = if (sep) |p| remaining[0..p] else remaining;
        remaining = if (sep) |p| remaining[p+1..] else &.{};

        if (component.len == 0) continue;

        current = findChildKey(data, current, component) orelse return null;
    }

    return current;
}

pub fn main(init: std.process.Init) void {
    var iter = std.process.Args.Iterator.init(init.minimal.args);
    _ = iter.next();

    var hive_path: ?[:0]const u8 = null;
    var export_mode = false;
    var merge_mode = false;
    var prefix: ?[]const u8 = null;
    var key_path: ?[]const u8 = null;

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--export")) {
            export_mode = true;
        } else if (std.mem.eql(u8, arg, "--merge")) {
            merge_mode = true;
        } else if (std.mem.eql(u8, arg, "--prefix")) {
            if (iter.next()) |p| {
                prefix = p;
            }
        } else if (std.mem.eql(u8, arg, "--unsafe")) {
            // ignored for now
        } else if (std.mem.eql(u8, arg, "--help")) {
            print("Usage: hivexregedit --export [--prefix PREFIX] hivefile key > regfile\n", .{});
            print("       hivexregedit --merge [--prefix PREFIX] hivefile [regfile]\n", .{});
            return;
        } else if (arg.len > 0 and arg[0] != '-') {
            if (hive_path == null) {
                hive_path = arg;
            } else if (key_path == null and export_mode) {
                key_path = arg;
            }
        }
    }

    if (hive_path == null) {
        print("Usage: hivexregedit --export [--prefix PREFIX] hivefile key > regfile\n", .{});
        print("       hivexregedit --merge [--prefix PREFIX] hivefile [regfile]\n", .{});
        return;
    }

    if (!export_mode and !merge_mode) {
        print("hivexregedit: use --export or --merge, see the manpage for help\n", .{});
        return;
    }

    if (export_mode) {
        if (key_path == null) {
            key_path = "\\";
        }

        var hive_file = hive.Hive.open(hive_path.?, true) catch |e| {
            print("hivexregedit: {s}: {s}\n", .{ hive_path.?, @errorName(e) });
            return;
        };
        defer hive_file.close();

        const data = hive_file.getData();
        if (data.len < 0x1024) {
            print("hivexregedit: {s}: file too small\n", .{hive_path.?});
            return;
        }

        print("Windows Registry Editor Version 5.00\n\n", .{});

        // Try to find the root key offset
        var root_nk_offset: usize = 0;

        // Find the root key - it's typically one of the first cells after hbin header
        const hbin_base: usize = 0x1000;

        // The root key has name_len=0 and should be among the first cells
        // Scan first 1024 bytes after hbin header to find the root key
        var scan_offset = hbin_base + 4; // Start after hbin header
        const scan_end = @min(scan_offset + 1024, data.len);
        while (scan_offset < scan_end - 80) {
            if (data[scan_offset] == 'n' and data[scan_offset + 1] == 'k') {
                // Use seg_len position for reading fields (scan_offset - 4)
                const seg_len_offset = scan_offset - 4;
                const subkey_count = readU32(data, seg_len_offset + 20);
                const name_len = readU16(data, seg_len_offset + 74);
                const subkey_index_off_stable = readI32(data, seg_len_offset + 24);
                const subkey_index_off_vol = readI32(data, seg_len_offset + 28);

                // Root key: name_len=0, has subkeys
                if (name_len == 0 and subkey_count > 0 and subkey_count < 10000) {
                    if (subkey_index_off_stable != 0 or subkey_index_off_vol != 0) {
                        // Use seg_len position (4 bytes before "nk") as the NK offset
                        root_nk_offset = seg_len_offset;
                        break;
                    }
                }
            }
            scan_offset += 4;
        }

        if (root_nk_offset == 0) {
            // Fallback: use the first NK cell we find
            // Note: root_nk_offset should be at seg_len position, not "nk" position
            for (hbin_base..@min(hbin_base + 8192, data.len)) |offset| {
                if (offset + 8 > data.len) break;
                if (data[offset] == 'n' and data[offset + 1] == 'k') {
                    // Use seg_len position (4 bytes before "nk")
                    root_nk_offset = offset - 4;
                    break;
                }
            }
        }

        if (root_nk_offset == 0) {
            print("hivexregedit: {s}: could not find root key\n", .{hive_path.?});
            return;
        }

        const nk_offset = resolvePath(data, root_nk_offset, key_path.?) orelse {
            print("hivexregedit: {s}: path not found in this hive\n", .{key_path.?});
            return;
        };

        var out = initByteList(65536);
        defer out.deinit(gpa);

        var full_path = initByteList(512);
        defer full_path.deinit(gpa);

        // Path starts empty, subkeys will add backslash + name
        exportKeyRecursive(data, nk_offset, &full_path, &out, true);

        writeStdout(out.items);
    } else {
        print("hivexregedit: merge mode not yet implemented in Zig version\n", .{});
        print("Use the system hivexregedit for merge operations.\n", .{});
    }
}
