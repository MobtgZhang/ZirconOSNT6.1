//! hivexml - Export Windows Registry Hive to XML format
//! 
//! This tool exports Windows Registry hive files to XML format using
//! the libhivex library.

const std = @import("std");
const hivex = @import("hivex");
const hive = hivex.hive;

const c = @cImport(@cInclude("unistd.h"));

/// Visit flags
pub const VisitFlags = struct {
    pub const SKIP_BAD: u32 = 0x0001;
};

/// Base64 encoding alphabet (RFC 4648)
const base64_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Write string to stdout using C write
fn writeStdout(buf: []const u8) void {
    _ = c.write(1, @ptrCast(buf.ptr), buf.len);
}

/// Encode data to Base64 with 76-char line wrapping - writes to stdout
fn encodeBase64(data: []const u8) void {
    var i: usize = 0;
    var line_len: usize = 0;
    const line_wrap = 76;

    var line_buf: [200]u8 = undefined;

    while (i + 3 <= data.len) : (i += 3) {
        if (line_len >= line_wrap) {
            @memcpy(line_buf[line_len..line_len+2], "\r\n");
            line_len += 2;
            writeStdout(line_buf[0..line_len]);
            line_len = 0;
        }

        const b0 = data[i];
        const b1 = data[i + 1];
        const b2 = data[i + 2];

        line_buf[line_len] = base64_alphabet[b0 >> 2];
        line_buf[line_len + 1] = base64_alphabet[((b0 & 0x03) << 4) | (b1 >> 4)];
        line_buf[line_len + 2] = base64_alphabet[((b1 & 0x0F) << 2) | (b2 >> 6)];
        line_buf[line_len + 3] = base64_alphabet[b2 & 0x3F];
        line_len += 4;
    }

    // Handle remaining bytes
    if (i < data.len) {
        if (line_len >= line_wrap) {
            @memcpy(line_buf[line_len..line_len+2], "\r\n");
            line_len += 2;
            writeStdout(line_buf[0..line_len]);
            line_len = 0;
        }

        const b0 = data[i];
        line_buf[line_len] = base64_alphabet[b0 >> 2];
        line_len += 1;
        
        if (i + 1 < data.len) {
            const b1 = data[i + 1];
            line_buf[line_len] = base64_alphabet[((b0 & 0x03) << 4) | (b1 >> 4)];
            line_buf[line_len + 1] = base64_alphabet[(b1 & 0x0F) << 2];
            line_len += 2;
        } else {
            line_buf[line_len] = base64_alphabet[(b0 & 0x03) << 4];
            line_buf[line_len + 1] = '=';
            line_len += 2;
        }
        line_buf[line_len] = '=';
        line_len += 1;
    }
    
    if (line_len > 0) {
        writeStdout(line_buf[0..line_len]);
    }
}

/// Escape XML special characters for element content - writes to stdout
fn xmlEscapeContent(content: []const u8) void {
    var line_buf: [200]u8 = undefined;
    var buf_pos: usize = 0;
    
    for (content) |char| {
        const escaped = switch (char) {
            '&' => "&amp;",
            '<' => "&lt;",
            '>' => "&gt;",
            else => null,
        };
        
        if (escaped) |s| {
            @memcpy(line_buf[buf_pos..buf_pos+s.len], s);
            buf_pos += s.len;
        } else {
            line_buf[buf_pos] = char;
            buf_pos += 1;
        }
        
        if (buf_pos > 180) {
            writeStdout(line_buf[0..buf_pos]);
            buf_pos = 0;
        }
    }
    
    if (buf_pos > 0) {
        writeStdout(line_buf[0..buf_pos]);
    }
}

/// Escape XML special characters for attributes - writes to stdout
fn xmlEscapeAttribute(content: []const u8) void {
    var line_buf: [200]u8 = undefined;
    var buf_pos: usize = 0;
    
    for (content) |char| {
        const escaped = switch (char) {
            '&' => "&amp;",
            '<' => "&lt;",
            '>' => "&gt;",
            '"' => "&quot;",
            '\'' => "&apos;",
            else => null,
        };
        
        if (escaped) |s| {
            @memcpy(line_buf[buf_pos..buf_pos+s.len], s);
            buf_pos += s.len;
        } else {
            line_buf[buf_pos] = char;
            buf_pos += 1;
        }
        
        if (buf_pos > 180) {
            writeStdout(line_buf[0..buf_pos]);
            buf_pos = 0;
        }
    }
    
    if (buf_pos > 0) {
        writeStdout(line_buf[0..buf_pos]);
    }
}

/// Windows FILETIME constants
const WINDOWS_TICK: i64 = 10_000_000;
const SEC_TO_UNIX_EPOCH: i64 = 11644473600;

/// Convert Windows FILETIME to ISO 8601 format string
fn filetimeTo8601(windows_ticks: i64) ?[32]u8 {
    if (windows_ticks == 0) return null;

    const unix_seconds = @divTrunc(windows_ticks, WINDOWS_TICK) - SEC_TO_UNIX_EPOCH;
    
    // Calculate days since Unix epoch
    const raw_days = @divTrunc(unix_seconds, @as(i64, 86400));
    if (raw_days < 0) return null;
    const remaining_seconds = @mod(unix_seconds, @as(i64, 86400));
    
    // Calculate year, month, day
    var year: u32 = 1970;
    var remaining_days: u64 = @intCast(raw_days);
    
    while (remaining_days >= 365) {
        const is_leap_yr = (@mod(year, 4) == 0) and ((@mod(year, 100) != 0) or (@mod(year, 400) == 0));
        const leap_years: u64 = if (is_leap_yr) 366 else 365;
        if (remaining_days < leap_years) break;
        remaining_days -= leap_years;
        year += 1;
    }
    
    const is_leap = (@mod(year, 4) == 0) and ((@mod(year, 100) != 0) or (@mod(year, 400) == 0));
    const days_in_month: []const u64 = if (is_leap) 
        &[_]u64{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    else
        &[_]u64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    
    var month: u32 = 1;
    for (days_in_month) |days_count| {
        if (remaining_days < days_count) break;
        remaining_days -= days_count;
        month += 1;
    }
    const day: u32 = @as(u32, @intCast(remaining_days + 1));
    
    // Calculate hours, minutes, seconds
    const hour = @divTrunc(remaining_seconds, 3600);
    const minute = @divTrunc(@mod(remaining_seconds, 3600), 60);
    const second = @mod(remaining_seconds, 60);
    
    var buf: [32]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d:0>4}-{:0>2}-{:0>2}T{:0>2}:{:0>2}:{:0>2}Z", .{
        year, month, day, hour, minute, second
    }) catch return null;
    
    var out: [32]u8 = undefined;
    @memcpy(&out, result);
    return out;
}

/// Get the hive last modified timestamp
fn getHiveMtime(hive_file: *hive.Hive) i64 {
    const hdr = hive_file.getHeader();
    return @as(i64, @bitCast(hdr.timestamp));
}

/// Check if UTF-16LE string is valid
fn isValidUtf16le(data: []const u8) bool {
    if (data.len % 2 != 0) return false;
    var i: usize = 0;
    while (i + 1 < data.len) : (i += 2) {
        const wc = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(data[i..i+2].ptr)), .little);
        if (wc == 0) break;
        if (wc >= 0xD800 and wc <= 0xDFFF) return false;
        if (wc > 0x10FFFF) return false;
    }
    return true;
}

/// Convert UTF-16LE to UTF-8 and return as allocated slice
fn utf16leToUtf8Alloc(data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var size: usize = 0;
    var i: usize = 0;
    while (i + 1 < data.len) : (i += 2) {
        const wc = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(data[i..i+2].ptr)), .little);
        if (wc == 0) break;
        if (wc < 0x80) {
            size += 1;
        } else if (wc < 0x800) {
            size += 2;
        } else if (wc < 0x10000) {
            size += 3;
        } else {
            size += 4;
        }
    }
    
    var result = try allocator.alloc(u8, size);
    errdefer allocator.free(result);
    
    i = 0;
    var j: usize = 0;
    while (i + 1 < data.len) : (i += 2) {
        const wc = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(data[i..i+2].ptr)), .little);
        if (wc == 0) break;
        
        if (wc < 0x80) {
            result[j] = @as(u8, @truncate(wc));
            j += 1;
        } else if (wc < 0x800) {
            result[j] = @as(u8, @truncate(0xC0 | (wc >> 6)));
            result[j + 1] = @as(u8, @truncate(0x80 | (wc & 0x3F)));
            j += 2;
        } else if (wc < 0x10000) {
            result[j] = @as(u8, @truncate(0xE0 | (wc >> 12)));
            result[j + 1] = @as(u8, @truncate(0x80 | ((wc >> 6) & 0x3F)));
            result[j + 2] = @as(u8, @truncate(0x80 | (wc & 0x3F)));
            j += 3;
        } else {
            result[j] = @as(u8, @truncate(0xF0 | (wc >> 18)));
            result[j + 1] = @as(u8, @truncate(0x80 | ((wc >> 12) & 0x3F)));
            result[j + 2] = @as(u8, @truncate(0x80 | ((wc >> 6) & 0x3F)));
            result[j + 3] = @as(u8, @truncate(0x80 | (wc & 0x3F)));
            j += 4;
        }
    }
    
    return result[0..j];
}

/// Value types
const ValueType = enum(u32) {
    NONE = 0x00000000,
    SZ = 0x00000001,
    EXPAND_SZ = 0x00000002,
    BINARY = 0x00000003,
    DWORD = 0x00000004,
    DWORD_BIG_ENDIAN = 0x00000005,
    LINK = 0x00000006,
    MULTI_SZ = 0x00000007,
    RESOURCE_LIST = 0x00000008,
    FULL_RESOURCE_DESCRIPTOR = 0x00000009,
    RESOURCE_REQUIREMENTS_LIST = 0x0000000A,
    QWORD = 0x0000000B,
};

/// Parse VK cell from data at offset
fn parseVkAt(data: []u8, offset: i32) ?hive.VkCell {
    if (offset < 4) return null;
    const abs_offset = @as(usize, @intCast(offset));
    if (abs_offset >= data.len) return null;
    return hive.VkCell.parse(data[abs_offset..]) catch return null;
}

/// Parse lf/lh cell at offset and get all NK offsets
fn parseLfCell(data: []u8, offset: i32, nk_offsets: *std.ArrayList(i32), allocator: std.mem.Allocator) bool {
    if (offset <= 0) return true;
    const abs_offset = @as(usize, @intCast(offset));
    if (abs_offset >= data.len) return true;

    const lf_cell = hive.LfCell.parse(data[abs_offset..]) catch return false;

    var i: usize = 0;
    while (i < lf_cell.count) : (i += 1) {
        const entry = lf_cell.getEntry(i) orelse continue;
        if (entry.nk_offset > 0) {
            nk_offsets.append(allocator, entry.nk_offset) catch {};
        }
    }

    return true;
}

/// Parse ri cell at offset and recursively get NK offsets
fn parseRiCell(data: []u8, offset: i32, nk_offsets: *std.ArrayList(i32), allocator: std.mem.Allocator) bool {
    if (offset <= 0) return true;
    const abs_offset = @as(usize, @intCast(offset));
    if (abs_offset >= data.len) return true;

    const ri_cell = hive.RiCell.parse(data[abs_offset..]) catch return false;

    var i: usize = 0;
    while (i < ri_cell.count) : (i += 1) {
        const sub_offset = ri_cell.getOffset(i) orelse continue;
        if (sub_offset > 0) {
            const sub_abs = @as(usize, @intCast(sub_offset));
            if (sub_abs < data.len and data.len >= sub_abs + 2) {
                const sig = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(data[sub_abs..sub_abs+2].ptr)), .little);
                if (sig == 0x6972) {
                    _ = parseRiCell(data, sub_offset, nk_offsets, allocator);
                } else {
                    _ = parseLfCell(data, sub_offset, nk_offsets, allocator);
                }
            }
        }
    }

    return true;
}

/// Write indentation
fn writeIndent(depth: usize) void {
    var buf: [200]u8 = undefined;
    var i: usize = 0;
    while (i < depth + 1) : (i += 1) {
        @memcpy(buf[i*2..i*2+2], "  ");
    }
    writeStdout(buf[0..(depth + 1) * 2]);
}

/// Write byte_runs for a node
fn writeNodeByteRuns(node_offset: i32, struct_length: usize) void {
    writeStdout("    <byte_runs>\n      <byte_run");
    var buf: [64]u8 = undefined;
    const len1 = std.fmt.bufPrint(&buf, " file_offset=\"{}\"", .{node_offset}) catch return;
    writeStdout(len1);
    const len2 = std.fmt.bufPrint(&buf, " len=\"{}\"", .{struct_length}) catch return;
    writeStdout(len2);
    writeStdout("/>\n    </byte_runs>\n");
}

/// Write byte_runs for a value
fn writeValueByteRuns(value_offset: i32, vk_struct_len: usize, data_offset: i32, data_len: usize) void {
    writeStdout("      <byte_runs>\n        <byte_run");
    var buf: [64]u8 = undefined;
    var len = std.fmt.bufPrint(&buf, " file_offset=\"{}\"", .{value_offset}) catch return;
    writeStdout(len);
    len = std.fmt.bufPrint(&buf, " len=\"{}\"", .{vk_struct_len}) catch return;
    writeStdout(len);
    writeStdout("/>");
    
    if (data_len > 4) {
        writeStdout("\n        <byte_run");
        len = std.fmt.bufPrint(&buf, " file_offset=\"{}\"", .{data_offset}) catch return;
        writeStdout(len);
        len = std.fmt.bufPrint(&buf, " len=\"{}\"", .{data_len}) catch return;
        writeStdout(len);
        writeStdout("/>");
    }
    
    writeStdout("\n      </byte_runs>\n");
}

/// Write value header
fn writeValueHeader(key: []const u8, value_type: []const u8, encoding: ?[]const u8, is_default: bool) void {
    writeStdout("  <value");
    writeStdout(" type=\"");
    writeStdout(value_type);
    writeStdout("\"");
    if (encoding) |enc| {
        writeStdout(" encoding=\"");
        writeStdout(enc);
        writeStdout("\"");
    }
    if (is_default) {
        writeStdout(" default=\"1\"");
    } else {
        writeStdout(" key=\"");
        xmlEscapeAttribute(key);
        writeStdout("\"");
    }
    writeStdout(" value=\"");
}

/// End a value element
fn endValue() void {
    writeStdout("\"/>\n");
}

/// Write a string value
fn writeValueString(vk_cell: hive.VkCell, key: []const u8, data: []u8, is_default: bool) void {
    const type_name: []const u8 = switch (@as(ValueType, @enumFromInt(vk_cell.value_type))) {
        .SZ => "string",
        .EXPAND_SZ => "expand",
        .LINK => "link",
        else => "unknown",
    };

    writeValueHeader(key, type_name, null, is_default);

    const str_data = vk_cell.getData(data) catch "";
    xmlEscapeContent(str_data);

    endValue();
    writeValueByteRuns(0, hive.VkCellHeader.SIZE, 0, str_data.len);
}

/// Write a multiple string value
fn writeValueMultiString(vk: hive.VkCell, key: []const u8, data: []u8, is_default: bool) void {
    writeStdout("  <value");
    writeStdout(" type=\"string-list\"");
    if (is_default) {
        writeStdout(" default=\"1\"");
    } else {
        writeStdout(" key=\"");
        xmlEscapeAttribute(key);
        writeStdout("\"");
    }
    writeStdout(">\n");

    const str_data = vk.getData(data) catch &.{};
    var offset: usize = 0;
    while (offset < str_data.len) {
        const null_pos = std.mem.indexOfScalar(u8, str_data[offset..], 0) orelse str_data.len - offset;
        if (null_pos == 0) {
            offset += 1;
            continue;
        }
        const substr = str_data[offset..offset + null_pos];
        writeStdout("    <string>");
        xmlEscapeContent(substr);
        writeStdout("</string>\n");
        offset += null_pos + 1;
    }

    writeStdout("  </value>\n");
    writeValueByteRuns(0, hive.VkCellHeader.SIZE, 0, str_data.len);
}

/// Write invalid UTF-16 string (base64 encoded)
fn writeValueInvalidUtf16(vk: hive.VkCell, key: []const u8, data: []u8, is_default: bool) void {
    const type_name: []const u8 = switch (@as(ValueType, @enumFromInt(vk.value_type))) {
        .SZ => "bad-string",
        .EXPAND_SZ => "bad-expand",
        .LINK => "bad-link",
        .MULTI_SZ => "bad-string-list",
        else => "unknown",
    };

    writeValueHeader(key, type_name, "base64", is_default);

    const str_data = vk.getData(data) catch &.{};
    encodeBase64(str_data);

    endValue();
    writeValueByteRuns(0, hive.VkCellHeader.SIZE, 0, str_data.len);
}

/// Write a DWORD value
fn writeValueDword(vk: hive.VkCell, key: []const u8, data: []u8, is_default: bool) void {
    const value = vk.readDword(data) catch 0;

    writeValueHeader(key, "int32", null, is_default);
    var buf: [32]u8 = undefined;
    const len = std.fmt.bufPrint(&buf, "{}", .{value}) catch return;
    writeStdout(len);

    endValue();
    writeValueByteRuns(0, hive.VkCellHeader.SIZE, 0, 4);
}

/// Write a QWORD value
fn writeValueQword(vk: hive.VkCell, key: []const u8, data: []u8, is_default: bool) void {
    const value = vk.readQword(data) catch 0;

    writeValueHeader(key, "int64", null, is_default);
    var buf: [32]u8 = undefined;
    const len = std.fmt.bufPrint(&buf, "{}", .{value}) catch return;
    writeStdout(len);

    endValue();
    writeValueByteRuns(0, hive.VkCellHeader.SIZE, 0, 8);
}

/// Write a binary value (base64 encoded)
fn writeValueBinary(vk: hive.VkCell, key: []const u8, data: []u8, is_default: bool) void {
    const bin_data = vk.getData(data) catch &.{};

    writeValueHeader(key, "binary", "base64", is_default);
    encodeBase64(bin_data);

    endValue();
    writeValueByteRuns(0, hive.VkCellHeader.SIZE, 0, bin_data.len);
}

/// Write a NONE value
fn writeValueNone(vk: hive.VkCell, key: []const u8, data: []u8, is_default: bool) void {
    const bin_data = vk.getData(data) catch &.{};

    writeValueHeader(key, "none", "base64", is_default);
    if (bin_data.len > 0) {
        encodeBase64(bin_data);
    }

    endValue();
    writeValueByteRuns(0, hive.VkCellHeader.SIZE, 0, bin_data.len);
}

/// Write an "other" type value
fn writeValueOther(vk: hive.VkCell, key: []const u8, data: []u8, is_default: bool) void {
    const type_name: []const u8 = switch (@as(ValueType, @enumFromInt(vk.value_type))) {
        .RESOURCE_LIST => "resource-list",
        .FULL_RESOURCE_DESCRIPTOR => "resource-description",
        .RESOURCE_REQUIREMENTS_LIST => "resource-requirements",
        else => "unknown",
    };

    const bin_data = vk.getData(data) catch &.{};

    writeValueHeader(key, type_name, "base64", is_default);
    if (bin_data.len > 0) {
        encodeBase64(bin_data);
    }

    endValue();
    writeValueByteRuns(0, hive.VkCellHeader.SIZE, 0, bin_data.len);
}

/// Traverse a node and write its values
fn traverseValues(nk: *const hive.NkCell, data: []u8, allocator: std.mem.Allocator) !void {
    if (!nk.hasValues()) return;

    const value_list_offset = nk.value_list_offset;
    if (value_list_offset <= 4) return;

    const abs_offset = @as(usize, @intCast(value_list_offset));
    if (abs_offset + 4 >= data.len) return;

    const count = std.mem.readInt(u32, @as(*const [4]u8, @ptrCast(data[abs_offset..abs_offset+4].ptr)), .little);

    var i: u32 = 0;
    while (i < count and i < nk.value_count) : (i += 1) {
        if (abs_offset + 4 + @as(usize, i) * 4 + 4 > data.len) break;
        const value_offset = std.mem.readInt(i32, @as(*const [4]u8, @ptrCast(data[abs_offset + 4 + @as(usize, i) * 4..abs_offset + 4 + @as(usize, i) * 4 + 4].ptr)), .little);

        const vk_cell_ptr = parseVkAt(data, value_offset);
        const vk_cell = vk_cell_ptr orelse continue;

        const key_bytes = if (vk_cell.name.len == 0) 
            try allocator.dupe(u8, "")
        else 
            try utf16leToUtf8Alloc(vk_cell.name, allocator);
        defer allocator.free(key_bytes);

        const is_default = key_bytes.len == 0;
        const vtype = @as(ValueType, @enumFromInt(vk_cell.value_type));

        switch (vtype) {
            .SZ, .EXPAND_SZ, .LINK => {
                if (isValidUtf16le(vk_cell.getData(data) catch &.{})) {
                    writeValueString(vk_cell, key_bytes, data, is_default);
                } else {
                    writeValueInvalidUtf16(vk_cell, key_bytes, data, is_default);
                }
            },
            .MULTI_SZ => {
                writeValueMultiString(vk_cell, key_bytes, data, is_default);
            },
            .DWORD, .DWORD_BIG_ENDIAN => {
                writeValueDword(vk_cell, key_bytes, data, is_default);
            },
            .QWORD => {
                writeValueQword(vk_cell, key_bytes, data, is_default);
            },
            .BINARY => {
                writeValueBinary(vk_cell, key_bytes, data, is_default);
            },
            .NONE => {
                writeValueNone(vk_cell, key_bytes, data, is_default);
            },
            .RESOURCE_LIST, .FULL_RESOURCE_DESCRIPTOR, .RESOURCE_REQUIREMENTS_LIST => {
                writeValueOther(vk_cell, key_bytes, data, is_default);
            },
        }
    }
}

/// Traverse a node and its subkeys recursively
fn traverseNode(nk_offset: i32, data: []u8, allocator: std.mem.Allocator, skip_bad: bool, is_root: bool, depth: usize) !void {
    if (nk_offset <= 0) return;

    const abs_offset = @as(usize, @intCast(nk_offset));
    if (abs_offset >= data.len) return;

    const nk = hive.NkCell.parse(data[abs_offset..]) catch {
        if (!skip_bad) return;
        return;
    };

    const key_name = utf16leToUtf8Alloc(nk.name, allocator) catch "";
    defer allocator.free(key_name);

    writeIndent(depth);
    writeStdout("<node");
    writeStdout(" name=\"");
    xmlEscapeAttribute(key_name);
    writeStdout("\"");

    if (is_root) {
        writeStdout(" root=\"1\"");
    }
    writeStdout(">\n");

    if (nk.timestamp != 0) {
        writeIndent(depth + 1);
        writeStdout("<mtime>");
        if (filetimeTo8601(@as(i64, @bitCast(nk.timestamp)))) |timebuf| {
            writeStdout(&timebuf);
        }
        writeStdout("</mtime>\n");
    }

    writeIndent(depth + 1);
    writeNodeByteRuns(nk_offset, hive.NkCellHeader.SIZE + nk.name.len);

    try traverseValues(&nk, data, allocator);

    var sub_offsets = std.ArrayList(i32).initCapacity(allocator, 16) catch return;
    defer sub_offsets.deinit(allocator);

    if (nk.subkey_index_offset_stable != 0) {
        const idx_abs = @as(usize, @intCast(nk.subkey_index_offset_stable));
        if (idx_abs < data.len and data.len >= idx_abs + 2) {
            const sig = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(data[idx_abs..idx_abs+2].ptr)), .little);
            if (sig == 0x6972) {
                _ = parseRiCell(data, nk.subkey_index_offset_stable, &sub_offsets, allocator);
            } else {
                _ = parseLfCell(data, nk.subkey_index_offset_stable, &sub_offsets, allocator);
            }
        }
    }

    if (nk.subkey_index_offset_volatile != 0) {
        const idx_abs = @as(usize, @intCast(nk.subkey_index_offset_volatile));
        if (idx_abs < data.len and data.len >= idx_abs + 2) {
            const sig = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(data[idx_abs..idx_abs+2].ptr)), .little);
            if (sig == 0x6972) {
                _ = parseRiCell(data, nk.subkey_index_offset_volatile, &sub_offsets, allocator);
            } else {
                _ = parseLfCell(data, nk.subkey_index_offset_volatile, &sub_offsets, allocator);
            }
        }
    }

    for (sub_offsets.items) |sub_offset| {
        try traverseNode(sub_offset, data, allocator, skip_bad, false, depth + 1);
    }

    writeIndent(depth);
    writeStdout("</node>\n");
}

pub fn main(init: std.process.Init) void {
    var iter = std.process.Args.Iterator.init(init.minimal.args);
    _ = iter.next();

    var open_flags: u32 = 0;
    var visit_flags: u32 = 0;
    var hive_path: ?[:0]const u8 = null;

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-d")) {
            open_flags |= 0x01;
        } else if (std.mem.eql(u8, arg, "-k")) {
            visit_flags |= VisitFlags.SKIP_BAD;
        } else if (std.mem.eql(u8, arg, "-u")) {
            open_flags |= 0x02;
        } else if (arg.len > 0 and arg[0] != '-') {
            hive_path = arg;
        }
    }

    if (hive_path == null) {
        std.debug.print("hivexml [-dku] regfile > output.xml\n", .{});
        std.debug.print("hivexml: missing name of input file\n", .{});
        std.process.exit(1);
    }

    const path = hive_path.?;

    var hive_file = hive.Hive.open(path, true) catch |e| {
        std.debug.print("hivexml: {s}: {s}\n", .{ path, @errorName(e) });
        std.process.exit(1);
    };
    defer hive_file.close();

    writeStdout("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    writeStdout("<hive>\n");

    const mtime = getHiveMtime(&hive_file);
    if (mtime != 0) {
        writeStdout("  <mtime>");
        if (filetimeTo8601(mtime)) |timebuf| {
            writeStdout(&timebuf);
        }
        writeStdout("</mtime>\n");
    }

    const data = hive_file.getData();
    const root_offset = hive_file.getRootOffset();
    const skip_bad = (visit_flags & VisitFlags.SKIP_BAD) != 0;

    traverseNode(root_offset, data, std.heap.page_allocator, skip_bad, true, 0) catch {
        std.debug.print("hivexml: failed to traverse hive\n", .{});
        std.process.exit(1);
    };

    writeStdout("</hive>\n");

    std.process.exit(0);
}
