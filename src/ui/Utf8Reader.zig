const std = @import("std");

reader: *std.Io.Reader,

pub fn init(reader: *std.Io.Reader) @This() {
    return .{ .reader = reader };
}

pub fn nextCodepoint(self: *@This()) !?u21 {
    const firstByteSlice = (self.reader.take(1)) catch |e| {
        switch (e) {
            error.EndOfStream => return null,
            else => return e,
        }
    };
    const firstByte = firstByteSlice[0];
    const codepointLength = try std.unicode.utf8ByteSequenceLength(firstByte);
    if (codepointLength == 1) {
        return @intCast(firstByte);
    }
    var buffer: [4]u8 = .{ firstByte, 0, 0, 0 };
    const nextBytes: []u8 = self.reader.take(codepointLength - 1) catch |e| {
        switch (e) {
            error.EndOfStream => return null,
            else => return e,
        }
    };

    @memcpy(buffer[1..codepointLength], nextBytes);

    return try std.unicode.utf8Decode(&buffer);
}
