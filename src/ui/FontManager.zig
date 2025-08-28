const std = @import("std");
const rl = @import("raylib");

const Font = @import("Font.zig");

const Key = i32;

const CacheHashMap = std.AutoArrayHashMap(Key, Font);

var charSet = blk: {
    const chars: []const u8 = " !\"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~" ++ "öüäÖÜÄßẞ";
    const n: usize = std.unicode.utf8CountCodepoints(chars) catch undefined;
    var array = std.mem.zeroes([n]i32);

    var viewer = std.unicode.Utf8View.initComptime(chars);
    var it = viewer.iterator();

    var index: usize = 0;
    while (it.nextCodepoint()) |cp| {
        array[index] = cp;
        index += 1;
    }
    break :blk array;
};

cache: CacheHashMap,

pub fn init(allocator: std.mem.Allocator) @This() {
    return @This(){ .cache = CacheHashMap.init(allocator) };
}

pub fn deinit(self: *@This()) void {
    self.cache.deinit();
}

pub fn getFont(self: *@This(), size: i32) Font {
    const path = "res/VictorMonoAll/VictorMono-Medium.otf";
    if (self.cache.get(size)) |font| {
        return font;
    }

    const raylibFont = rl.loadFontEx(path, size, &charSet) catch @panic("font loading failed");
    rl.setTextureFilter(raylibFont.texture, .bilinear);
    const fontMeasurement = rl.measureTextEx(raylibFont, "A", @floatFromInt(size), Font.SPACING);
    const font: Font = .{
        .raylibFont = raylibFont,
        .width = fontMeasurement.x,
        .height = fontMeasurement.y,
    };
    self.cache.put(size, font) catch @panic("self.cache.put() failed");
    return font;
}
