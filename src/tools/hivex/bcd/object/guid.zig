//! BCD Object GUID Definitions
//! 
//! Defines well-known BCD GUIDs and GUID utilities.

const std = @import("std");

/// GUID structure (Windows style)
pub const GUID = extern struct {
    /// Data1 (4 bytes)
    data1: u32,

    /// Data2 (2 bytes)
    data2: u16,

    /// Data3 (2 bytes)
    data3: u16,

    /// Data4 (8 bytes)
    data4: [8]u8,

    /// Parse GUID from string (e.g., "{12345678-1234-1234-1234-123456789abc}")
    pub fn parse(str: []const u8) !GUID {
        if (str.len < 38 or str[0] != '{') {
            return error.InvalidFormat;
        }

        var guid = GUID{
            .data1 = 0,
            .data2 = 0,
            .data3 = 0,
            .data4 = .{0} ** 8,
        };

        const hex_str = str[1..37];

        inline for (.{ 8, 13, 18, 23 }) |pos| {
            if (hex_str[pos] != '-') {
                return error.InvalidFormat;
            }
        }

        guid.data1 = try parseHex32(hex_str[0..8]);
        guid.data2 = try parseHex16(hex_str[9..13]);
        guid.data3 = try parseHex16(hex_str[14..18]);
        guid.data4[0] = try parseHex8(hex_str[19..21]);
        guid.data4[1] = try parseHex8(hex_str[21..23]);
        guid.data4[2] = try parseHex8(hex_str[24..26]);
        guid.data4[3] = try parseHex8(hex_str[26..28]);
        guid.data4[4] = try parseHex8(hex_str[28..30]);
        guid.data4[5] = try parseHex8(hex_str[30..32]);
        guid.data4[6] = try parseHex8(hex_str[32..34]);
        guid.data4[7] = try parseHex8(hex_str[34..36]);

        return guid;
    }

    /// Format GUID to string
    pub fn format(self: *const GUID, allocator: std.mem.Allocator) ![]u8 {
        var buf: [38]u8 = undefined;
        self.formatStatic(&buf);
        return try allocator.dupe(u8, &buf);
    }

    /// Format GUID to static buffer
    pub fn formatStatic(self: *const GUID, buf: *[38]u8) void {
        // Format: {XXXXXXXX-XXXX-XXXX-XX...
        var pos: usize = 0;
        
        // Helper to write hex byte
        const hex_chars = "0123456789ABCDEF";
        
        buf[pos] = '{'; pos += 1;
        
        // data1 (8 hex digits)
        buf[pos] = hex_chars[(self.data1 >> 28) & 0xF]; pos += 1;
        buf[pos] = hex_chars[(self.data1 >> 24) & 0xF]; pos += 1;
        buf[pos] = hex_chars[(self.data1 >> 20) & 0xF]; pos += 1;
        buf[pos] = hex_chars[(self.data1 >> 16) & 0xF]; pos += 1;
        buf[pos] = hex_chars[(self.data1 >> 12) & 0xF]; pos += 1;
        buf[pos] = hex_chars[(self.data1 >> 8) & 0xF]; pos += 1;
        buf[pos] = hex_chars[(self.data1 >> 4) & 0xF]; pos += 1;
        buf[pos] = hex_chars[self.data1 & 0xF]; pos += 1;
        
        buf[pos] = '-'; pos += 1;
        
        // data2 (4 hex digits)
        buf[pos] = hex_chars[(self.data2 >> 12) & 0xF]; pos += 1;
        buf[pos] = hex_chars[(self.data2 >> 8) & 0xF]; pos += 1;
        buf[pos] = hex_chars[(self.data2 >> 4) & 0xF]; pos += 1;
        buf[pos] = hex_chars[self.data2 & 0xF]; pos += 1;
        
        buf[pos] = '-'; pos += 1;
        
        // data3 (4 hex digits)
        buf[pos] = hex_chars[(self.data3 >> 12) & 0xF]; pos += 1;
        buf[pos] = hex_chars[(self.data3 >> 8) & 0xF]; pos += 1;
        buf[pos] = hex_chars[(self.data3 >> 4) & 0xF]; pos += 1;
        buf[pos] = hex_chars[self.data3 & 0xF]; pos += 1;
        
        buf[pos] = '-'; pos += 1;
        
        // data4 first 2 bytes (4 hex digits)
        for (self.data4[0..2]) |b| {
            buf[pos] = hex_chars[(b >> 4) & 0xF]; pos += 1;
            buf[pos] = hex_chars[b & 0xF]; pos += 1;
        }
        
        buf[pos] = '-'; pos += 1;
        
        // data4 remaining 6 bytes (12 hex digits)
        for (self.data4[2..8]) |b| {
            buf[pos] = hex_chars[(b >> 4) & 0xF]; pos += 1;
            buf[pos] = hex_chars[b & 0xF]; pos += 1;
        }
        
        buf[pos] = '}'; pos += 1;
    }

    /// Compare two GUIDs
    pub fn eql(self: *const GUID, other: *const GUID) bool {
        return self.data1 == other.data1 and
            self.data2 == other.data2 and
            self.data3 == other.data3 and
            std.mem.eql(u8, &self.data4, &other.data4);
    }

    /// Check if GUID is null
    pub fn isNull(self: *const GUID) bool {
        return self.data1 == 0 and self.data2 == 0 and self.data3 == 0 and
            std.mem.allEqual(u8, &self.data4, 0);
    }

    /// Generate a new random GUID
    pub fn generate() GUID {
        var guid: GUID = undefined;
        guid.data1 = std.crypto.random.int(u32);
        guid.data2 = std.crypto.random.int(u16);
        guid.data3 = std.crypto.random.int(u16);
        std.crypto.random.bytes(&guid.data4);
        return guid;
    }

    /// Get as bytes (little-endian)
    pub fn asBytes(self: *const GUID) [@sizeOf(GUID)]u8 {
        var bytes: [@sizeOf(GUID)]u8 = undefined;
        std.mem.writeInt(u32, bytes[0..4], self.data1, .little);
        std.mem.writeInt(u16, bytes[4..6], self.data2, .little);
        std.mem.writeInt(u16, bytes[6..8], self.data3, .little);
        @memcpy(bytes[8..16], &self.data4);
        return bytes;
    }

    /// Create from bytes (little-endian)
    pub fn fromBytes(bytes: []const u8) !GUID {
        if (bytes.len < 16) return error.BufferTooSmall;
        return GUID{
            .data1 = std.mem.readInt(u32, bytes[0..4], .little),
            .data2 = std.mem.readInt(u16, bytes[4..6], .little),
            .data3 = std.mem.readInt(u16, bytes[6..8], .little),
            .data4 = bytes[8..16].*,
        };
    }
};

fn parseHex8(str: []const u8) !u8 {
    if (str.len != 2) return error.InvalidFormat;
    return try parseHexN(u8, str);
}

fn parseHex16(str: []const u8) !u16 {
    if (str.len != 4) return error.InvalidFormat;
    return try parseHexN(u16, str);
}

fn parseHex32(str: []const u8) !u32 {
    if (str.len != 8) return error.InvalidFormat;
    return try parseHexN(u32, str);
}

fn parseHexN(comptime T: type, str: []const u8) !T {
    var result: T = 0;
    for (str) |c| {
        result = result << 4;
        result |= switch (c) {
            '0'...'9' => c - '0',
            'a'...'f' => c - 'a' + 10,
            'A'...'F' => c - 'A' + 10,
            else => return error.InvalidCharacter,
        };
    }
    return result;
}

/// Well-known BCD GUIDs
pub const WellKnownGuid = struct {
    /// Boot Manager
    pub fn bootmgr() GUID {
        return GUID{
            .data1 = 0x9dea862c,
            .data2 = 0x5cab,
            .data3 = 0x444b,
            .data4 = .{ 0x8b, 0x4c, 0x15, 0x9b, 0x5f, 0x5e, 0x5d, 0xf8 },
        };
    }

    /// Boot loaders collection
    pub fn bootloaders() GUID {
        return GUID{
            .data1 = 0x47f257e3,
            .data2 = 0x7e48,
            .data3 = 0x4501,
            .data4 = .{ 0x81, 0x98, 0x77, 0x77, 0x5c, 0x3f, 0x97, 0x81 },
        };
    }

    /// Default operating system
    pub fn default() GUID {
        return GUID{
            .data1 = 0xa5a0b4e4,
            .data2 = 0xfea1,
            .data3 = 0x4f88,
            .data4 = .{ 0x94, 0xfb, 0x4c, 0x52, 0xea, 0xfa, 0xb8, 0x77 },
        };
    }

    /// Current boot entry
    pub fn current() GUID {
        return GUID{
            .data1 = 0xfa926493,
            .data2 = 0x6f1a,
            .data3 = 0x47c1,
            .data4 = .{ 0xa0, 0x82, 0x0e, 0xe8, 0x69, 0x8b, 0xcd, 0x62 },
        };
    }

    /// Memory diagnostic application
    pub fn memdiag() GUID {
        return GUID{
            .data1 = 0x4637306d,
            .data2 = 0x000f,
            .data3 = 0x417f,
            .data4 = .{ 0x86, 0xc4, 0xac, 0xba, 0x6f, 0x05, 0xab, 0x14 },
        };
    }

    /// Resume from hibernate
    pub fn resume_hibernate() GUID {
        return GUID{
            .data1 = 0x1afa9c44,
            .data2 = 0x5dd5,
            .data3 = 0x4b5a,
            .data4 = .{ 0xbf, 0x1b, 0xef, 0x4a, 0xf6, 0x8e, 0x0c, 0x2f },
        };
    }

    /// Resume filter
    pub fn resumefilter() GUID {
        return GUID{
            .data1 = 0x7d883816,
            .data2 = 0x8185,
            .data3 = 0x4afc,
            .data4 = .{ 0xa2, 0xde, 0x26, 0x7b, 0xc5, 0x2a, 0x2e, 0x6d },
        };
    }

    /// Setup loader
    pub fn setup() GUID {
        return GUID{
            .data1 = 0x9ce2bf13,
            .data2 = 0xbf4f,
            .data3 = 0x4b1b,
            .data4 = .{ 0xa6, 0x5c, 0x8a, 0x8e, 0x73, 0xf8, 0x5b, 0x53 },
        };
    }

    /// Recovery OS
    pub fn recovery() GUID {
        return GUID{
            .data1 = 0x1afd3926,
            .data2 = 0xaf4a,
            .data3 = 0x4570,
            .data4 = .{ 0x84, 0x7f, 0xeb, 0x69, 0x8a, 0x3d, 0xde, 0x95 },
        };
    }

    /// Diagnostic application
    pub fn diag() GUID {
        return GUID{
            .data1 = 0x28475539,
            .data2 = 0x677a,
            .data3 = 0x4b94,
            .data4 = .{ 0xa9, 0x77, 0x8b, 0x0d, 0x5b, 0x90, 0x89, 0xa6 },
        };
    }

    /// Failed boot entry
    pub fn failed() GUID {
        return GUID{
            .data1 = 0x6ef5f3de,
            .data2 = 0x3b7a,
            .data3 = 0x4596,
            .data4 = .{ 0xa4, 0xb8, 0x4b, 0x4a, 0x3a, 0x7f, 0x5e, 0x6e },
        };
    }

    /// Debugger settings
    pub fn dbgsettings() GUID {
        return GUID{
            .data1 = 0x96ebcb27,
            .data2 = 0x19c4,
            .data3 = 0x44f5,
            .data4 = .{ 0xb2, 0xf2, 0x7b, 0x89, 0x92, 0x1d, 0x5a, 0xfc },
        };
    }

    /// Hypervisor settings
    pub fn hypervisor() GUID {
        return GUID{
            .data1 = 0x91866eba,
            .data2 = 0x0a2c,
            .data3 = 0x4a1e,
            .data4 = .{ 0xa2, 0x47, 0x6f, 0x54, 0x95, 0x3c, 0xc9, 0x4c },
        };
    }

    /// Real mode
    pub fn realmode() GUID {
        return GUID{
            .data1 = 0x466,
            .data2 = 0x3a6e,
            .data3 = 0x4a01,
            .data4 = .{ 0xa4, 0x9b, 0x36, 0x7c, 0xc7, 0x5a, 0x8b, 0x7a },
        };
    }

    /// Bad memory entry
    pub fn bad() GUID {
        return GUID{
            .data1 = 0x3c9e0e45,
            .data2 = 0x10d7,
            .data3 = 0x4f8a,
            .data4 = .{ 0xa4, 0x6f, 0x01, 0x8e, 0x8c, 0xd2, 0x07, 0x5b },
        };
    }

    /// Get GUID by name
    pub fn getByName(name: []const u8) ?GUID {
        if (std.mem.eql(u8, name, "bootmgr")) return bootmgr();
        if (std.mem.eql(u8, name, "bootloaders")) return bootloaders();
        if (std.mem.eql(u8, name, "default")) return default();
        if (std.mem.eql(u8, name, "current")) return current();
        if (std.mem.eql(u8, name, "memdiag")) return memdiag();
        if (std.mem.eql(u8, name, "resume_hibernate")) return resume_hibernate();
        if (std.mem.eql(u8, name, "resumefilter")) return resumefilter();
        if (std.mem.eql(u8, name, "setup")) return setup();
        if (std.mem.eql(u8, name, "recovery")) return recovery();
        if (std.mem.eql(u8, name, "diag")) return diag();
        if (std.mem.eql(u8, name, "failed")) return failed();
        if (std.mem.eql(u8, name, "dbgsettings")) return dbgsettings();
        if (std.mem.eql(u8, name, "hypervisor")) return hypervisor();
        if (std.mem.eql(u8, name, "realmode")) return realmode();
        if (std.mem.eql(u8, name, "bad")) return bad();
        return null;
    }

    /// Get name by GUID
    pub fn getNameByGuid(guid: *const GUID) ?[]const u8 {
        if (guid.eql(&bootmgr())) return "bootmgr";
        if (guid.eql(&bootloaders())) return "bootloaders";
        if (guid.eql(&default())) return "default";
        if (guid.eql(&current())) return "current";
        if (guid.eql(&memdiag())) return "memdiag";
        if (guid.eql(&resume_hibernate())) return "resume_hibernate";
        if (guid.eql(&resumefilter())) return "resumefilter";
        if (guid.eql(&setup())) return "setup";
        if (guid.eql(&recovery())) return "recovery";
        if (guid.eql(&diag())) return "diag";
        if (guid.eql(&failed())) return "failed";
        if (guid.eql(&dbgsettings())) return "dbgsettings";
        if (guid.eql(&hypervisor())) return "hypervisor";
        if (guid.eql(&realmode())) return "realmode";
        if (guid.eql(&bad())) return "bad";
        return null;
    }

    /// Get description by GUID
    pub fn getDescriptionByGuid(guid: *const GUID) ?[]const u8 {
        const name = getNameByGuid(guid) orelse return null;
        return getDescriptionByName(name);
    }

    /// Get description by name
    pub fn getDescriptionByName(name: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, name, "bootmgr")) return "Boot Manager";
        if (std.mem.eql(u8, name, "bootloaders")) return "Boot Loaders Collection";
        if (std.mem.eql(u8, name, "default")) return "Default OS Loader";
        if (std.mem.eql(u8, name, "current")) return "Current Boot Entry";
        if (std.mem.eql(u8, name, "memdiag")) return "Memory Diagnostic";
        if (std.mem.eql(u8, name, "resume_hibernate")) return "Resume from Hibernate";
        if (std.mem.eql(u8, name, "resumefilter")) return "Resume Filter";
        if (std.mem.eql(u8, name, "setup")) return "Setup Loader";
        if (std.mem.eql(u8, name, "recovery")) return "Recovery Environment";
        if (std.mem.eql(u8, name, "diag")) return "Diagnostic Application";
        if (std.mem.eql(u8, name, "failed")) return "Failed Boot Entry";
        if (std.mem.eql(u8, name, "dbgsettings")) return "Debugger Settings";
        if (std.mem.eql(u8, name, "hypervisor")) return "Hypervisor Settings";
        if (std.mem.eql(u8, name, "realmode")) return "Real Mode Boot";
        if (std.mem.eql(u8, name, "bad")) return "Bad Memory Entry";
        return null;
    }

    /// Check if GUID is well-known
    pub fn isWellKnown(guid: *const GUID) bool {
        return getNameByGuid(guid) != null;
    }
};

/// Error types
pub const Error = error{
    InvalidFormat,
    InvalidCharacter,
    BufferTooSmall,
    UnknownGuid,
};
