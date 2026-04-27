//! BCD Dump Tool
//! 
//! Dumps BCD store contents in human-readable format.

const std = @import("std");
const hivex = @import("hivex");

const bcd = hivex.bcd;

/// Dump the BCD store
pub fn dumpStore(path: []const u8) !void {
    var store = try bcd.BcdStore.open(path);
    defer store.close();

    const format: bcd.BcdTextFormat = .Compact;
    var text_writer = try bcd.BcdTextWriter.init(std.heap.page_allocator, format);
    defer text_writer.deinit();

    try text_writer.writeStoreHeader(path, store.objects.items.len);

    for (store.objects.items) |*obj| {
        try text_writer.writeObject(obj);
    }

    const output = text_writer.getOutput();
    std.debug.print("{s}", .{output});
}

/// Main entry point
pub fn main() !void {
    const path = "/boot/efi/EFI/Microsoft/Boot/BCD";
    
    dumpStore(path) catch |e| {
        std.debug.print("Error: {}\n", .{e});
        return;
    };
}
