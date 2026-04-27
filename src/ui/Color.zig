const std = @import("std");

r: u8,
g: u8,
b: u8,
a: u8,

pub fn init(r: u8, g: u8, b: u8, a: u8) @This() {
    return .{ .r = r, .g = g, .b = b, .a = a };
}

pub fn random() @This() {
    var seed: u64 = undefined;
    _ = std.os.linux.getrandom(@ptrCast(&seed), @sizeOf(u64), 0);
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    return .{
        .r = std.math.clamp(rand.int(u8), 50, 200),
        .g = std.math.clamp(rand.int(u8), 50, 200),
        .b = std.math.clamp(rand.int(u8), 50, 200),
        .a = 255,
    };
}
