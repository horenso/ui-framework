const std = @import("std");
const rl = @import("raylib");

const Key = i32;

const CacheHashMap = std.AutoArrayHashMap(Key, rl.Font);

const raw: []const u8 = " !\"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~" ++ "öüäÖÜÄßẞ";

var charSet = blk: {
    const n: usize = std.unicode.utf8CountCodepoints(raw) catch undefined;
    var array = std.mem.zeroes([n]i32);

    var viewer = std.unicode.Utf8View.initComptime(raw);
    var it = viewer.iterator();

    var index: usize = 0;
    while (it.nextCodepoint()) |cp| {
        array[index] = cp;
        index += 1;
    }
    break :blk array;
};

// const charSet: []const i32 = toUnicodeSlice(raw);

// fn toUnicodeSlice(comptime s: []const u8) []const i32 {
//     var viewer = std.unicode.Utf8View.initComptime(s);
//     var it = viewer.iterator();
//     const n = std.unicode.utf8CountCodepoints(s) catch undefined;
//     var array = std.mem.zeroes([n]i32);

//     var index: usize = 0;
//     while (it.nextCodepoint()) |cp| {
//         array[index] = cp;
//         index += 1;
//     }
//     return &array;
// }

cache: CacheHashMap,

pub fn init(allocator: std.mem.Allocator) @This() {
    return @This(){ .cache = CacheHashMap.init(allocator) };
}

pub fn deinit(self: *@This()) void {
    self.cache.deinit();
}

pub fn getFont(self: *@This(), size: i32) !rl.Font {
    const path = "res/VictorMonoAll/VictorMono-Medium.ttf";
    if (self.cache.get(size)) |font| {
        return font;
    }
    const font = try rl.loadFontEx(path, size, &charSet);
    rl.setTextureFilter(font.texture, .bilinear);
    try self.cache.put(size, font);
    return font;
}
