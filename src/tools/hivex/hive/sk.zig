//! Registry Hive Security Descriptor (SK) Cell
//! 
//! SK cells contain Windows security descriptors for registry keys.

const std = @import("std");
const Self = @This();

/// SK cell signature "sk"
pub const SIGNATURE: [2]u8 = .{ 's', 'k' };

/// SK Cell header structure
pub const Header = extern struct {
    /// "sk" signature (2 bytes)
    signature: u16,

    /// Reserved (2 bytes)
    reserved: u16,

    /// Offset to previous SK cell (4 bytes)
    offset_to_prev_sk: i32,

    /// Offset to next SK cell (4 bytes)
    offset_to_next_sk: i32,

    /// Reference count (4 bytes)
    reference_count: u32,

    /// Security descriptor length (4 bytes)
    security_descriptor_length: u32,

    /// Fixed part size
    pub const SIZE: usize = 20;
};

/// Security descriptor header (Windows SECURITY_DESCRIPTOR_RELATIVE)
pub const SecurityDescriptorHeader = struct {
    /// Revision (1 byte)
    revision: u8,

    /// Sbz1 (1 byte)
    sbz1: u8,

    /// Control flags (2 bytes)
    control: u16,

    /// Owner SID offset (4 bytes)
    owner_offset: u32,

    /// Group SID offset (4 bytes)
    group_offset: u32,

    /// DACL offset (4 bytes)
    dacl_offset: u32,

    /// SACL offset (4 bytes)
    sacl_offset: u32,

    /// Header size
    pub const SIZE: usize = 20;
};

/// Security descriptor control flags
pub const SdControl = struct {
    pub const SE_OWNER_DEFAULTED: u16 = 0x0001;
    pub const SE_GROUP_DEFAULTED: u16 = 0x0002;
    pub const SE_DACL_PRESENT: u16 = 0x0004;
    pub const SE_DACL_DEFAULTED: u16 = 0x0008;
    pub const SE_SACL_PRESENT: u16 = 0x0010;
    pub const SE_SACL_DEFAULTED: u16 = 0x0020;
    pub const SE_DACL_AUTO_INHERIT_REQ: u16 = 0x0100;
    pub const SE_SACL_AUTO_INHERIT_REQ: u16 = 0x0200;
    pub const SE_DACL_AUTO_INHERITED: u16 = 0x0400;
    pub const SE_SACL_AUTO_INHERITED: u16 = 0x0800;
    pub const SE_DACL_PROTECTED: u16 = 0x1000;
    pub const SE_SACL_PROTECTED: u16 = 0x2000;
    pub const SE_RM_CONTROL_VALID: u16 = 0x4000;
    pub const SE_SELF_RELATIVE: u16 = 0x8000;
};

/// Parsed SK Cell
pub const SkCell = struct {
    /// Offset to previous SK
    offset_to_prev_sk: i32,

    /// Offset to next SK
    offset_to_next_sk: i32,

    /// Reference count
    reference_count: u32,

    /// Security descriptor length
    security_descriptor_length: u32,

    /// Security descriptor data
    security_descriptor: []const u8,

    /// Raw data
    raw_data: []const u8,

    /// Parse an SK cell from raw data
    pub fn parse(data: []const u8) !SkCell {
        if (data.len < Header.SIZE) {
            return error.BufferTooSmall;
        }

        if (std.mem.readInt(u16, data[0..2], .little) != 0x6B73) {
            return error.InvalidSignature;
        }

        const sd_len = std.mem.readInt(u32, data[16..20], .little);

        return SkCell{
            .offset_to_prev_sk = std.mem.readInt(i32, data[4..8], .little),
            .offset_to_next_sk = std.mem.readInt(i32, data[8..12], .little),
            .reference_count = std.mem.readInt(u32, data[12..16], .little),
            .security_descriptor_length = sd_len,
            .security_descriptor = data[Header.SIZE..Header.SIZE + sd_len],
            .raw_data = data,
        };
    }

    /// Get the security descriptor header
    pub fn getSecurityDescriptor(self: *const SkCell) ?SecurityDescriptorHeader {
        if (self.security_descriptor.len < SecurityDescriptorHeader.SIZE) {
            return null;
        }
        const sd = self.security_descriptor;
        return SecurityDescriptorHeader{
            .revision = sd[0],
            .sbz1 = sd[1],
            .control = std.mem.readInt(u16, sd[2..4], .little),
            .owner_offset = std.mem.readInt(u32, sd[4..8], .little),
            .group_offset = std.mem.readInt(u32, sd[8..12], .little),
            .dacl_offset = std.mem.readInt(u32, sd[12..16], .little),
            .sacl_offset = std.mem.readInt(u32, sd[16..20], .little),
        };
    }

    /// Check if the security descriptor has a DACL
    pub fn hasDacl(self: *const SkCell) bool {
        const hdr = self.getSecurityDescriptor() orelse return false;
        return (hdr.control & SdControl.SE_DACL_PRESENT) != 0;
    }

    /// Check if the security descriptor has a SACL
    pub fn hasSacl(self: *const SkCell) bool {
        const hdr = self.getSecurityDescriptor() orelse return false;
        return (hdr.control & SdControl.SE_SACL_PRESENT) != 0;
    }

    /// Check if the security descriptor is self-relative
    pub fn isSelfRelative(self: *const SkCell) bool {
        const hdr = self.getSecurityDescriptor() orelse return false;
        return (hdr.control & SdControl.SE_SELF_RELATIVE) != 0;
    }

    /// Increment the reference count
    pub fn incrementRef(self: *SkCell) void {
        self.reference_count += 1;
    }

    /// Decrement the reference count
    pub fn decrementRef(self: *SkCell) void {
        if (self.reference_count > 0) {
            self.reference_count -= 1;
        }
    }

    /// Check if this is the last reference
    pub fn isLastReference(self: *const SkCell) bool {
        return self.reference_count == 0;
    }
};

/// Serialize an SK cell
pub fn serialize(sk: *const SkCell, data: []u8) !void {
    if (data.len < Header.SIZE + sk.security_descriptor_length) {
        return error.BufferTooSmall;
    }

    @memset(data[0..data.len], 0);

    std.mem.writeInt(u16, data[0..2], 0x6B73, .little);
    std.mem.writeInt(i32, data[4..8], sk.offset_to_prev_sk, .little);
    std.mem.writeInt(i32, data[8..12], sk.offset_to_next_sk, .little);
    std.mem.writeInt(u32, data[12..16], sk.reference_count, .little);
    std.mem.writeInt(u32, data[16..20], sk.security_descriptor_length, .little);

    @memcpy(data[Header.SIZE..Header.SIZE + sk.security_descriptor_length], sk.security_descriptor);
}

/// Create an SK cell with default security
pub fn createDefault(owner_sid: []const u8, dacl: []const u8) SkCell {
    return SkCell{
        .offset_to_prev_sk = 0,
        .offset_to_next_sk = 0,
        .reference_count = 1,
        .security_descriptor_length = @as(u32, @intCast(owner_sid.len + dacl.len + SecurityDescriptorHeader.SIZE)),
        .security_descriptor = &.{},
        .raw_data = &.{},
    };
}

/// Error types
pub const Error = error{
    BufferTooSmall,
    InvalidSignature,
    InvalidOffset,
    InvalidData,
};
