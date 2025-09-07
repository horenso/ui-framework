const std = @import("std");
const tt = @import("truetype");

pub const Font = struct {
    pub const SPACING = 0.0;

    width: f32,
    height: f32,
    // font: tt.TrueType,
};

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

pub fn getFont(self: *@This(), allocator: std.mem.Allocator, size: i32) !Font {
    _ = self;
    _ = allocator;
    _ = size;
    unreachable;
    // const path = "res/VictorMonoAll/VictorMono-Medium.otf";

    // if (self.cache.get(size)) |font| {
    //     return font;
    // }

    // const font_bytes = try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
    // defer allocator.free(font_bytes);

    // const f = try tt.load(font_bytes);

    // const idx = tt.codepointGlyphIndex('A') orelse return error.GlyphResolveError;
    // const metrics = tt.glyphHMetrics(idx);

    // const font: Font = .{
    //     .tt = f,
    //     .width = @floatFromInt(metrics.advance_width),
    //     .height = @floatFromInt(size),
    // };

    // try self.cache.put(size, font);
    // return font;
}
