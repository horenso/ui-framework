const std = @import("std");
const sdl = @import("sdl.zig").sdl;

const freetype = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
});

const vec = @import("./vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const Vec2i = vec.Vec2i;

const Key = i32;
const Renderer = @import("Renderer.zig");

const FONT_PATH = "res/VictorMonoAll/VictorMono-Medium.ttf";

library: freetype.FT_Library,
fontFace: *freetype.FT_FaceRec,
cache: std.AutoArrayHashMap(Key, *FontAtlas),

pub fn init(allocator: std.mem.Allocator) !@This() {
    var library: freetype.FT_Library = undefined;
    const initError = freetype.FT_Init_FreeType(&library);
    if (initError != 0) {
        return error.FreeTypeInitError;
    }

    var fontFace: freetype.FT_Face = undefined;
    const fontFaceLoadingError = freetype.FT_New_Face(library, FONT_PATH, 0, &fontFace);
    if (fontFaceLoadingError != 0) {
        _ = freetype.FT_Done_FreeType(library);
        return error.FontLoadingError;
    }

    return @This(){
        .library = library,
        .fontFace = fontFace,
        .cache = .init(allocator),
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    for (self.cache.values()) |fontAtlas| {
        fontAtlas.glyphs.deinit(allocator);
        allocator.destroy(fontAtlas);
    }
    self.cache.deinit();

    var err: c_int = 0;
    err += freetype.FT_Done_Face(self.fontFace);
    err += freetype.FT_Done_FreeType(self.library);

    if (err != 0) {
        std.log.debug("font uninit failed!", .{});
    }
}

pub fn getFontAtlas(
    self: *@This(),
    allocator: std.mem.Allocator,
    renderer: Renderer,
    size: i32,
) !*FontAtlas {
    if (self.cache.get(size)) |atlas| {
        return atlas;
    }

    // font face is global for now
    // 0 here means the width is automatic
    // TODO error handling
    _ = freetype.FT_Set_Pixel_Sizes(self.fontFace, 0, @intCast(size));

    const metrics = self.fontFace.*.size.*.metrics;

    const width: f32 = @floatFromInt(metrics.max_advance >> 6);
    const height: f32 = @floatFromInt(metrics.height >> 6);
    const baseline: f32 = @floatFromInt(metrics.descender >> 6);

    // Create SDL texture atlas (RGBA or A8)
    const texture = sdl.SDL_CreateTexture(
        renderer.sdlRenderer,
        sdl.SDL_PIXELFORMAT_RGBA32,
        sdl.SDL_TEXTUREACCESS_STREAMING,
        1024,
        1024,
    ) orelse return error.SDLError;

    const atlas = try allocator.create(FontAtlas);
    atlas.* = .{
        .fontFace = self.fontFace,
        .texture = texture,
        .glyphs = .empty,
        .nextX = 0,
        .nextY = 0,
        .rowHeight = 0,
        .fontSize = size,
        .width = width,
        .height = height,
        .baseline = baseline,
    };
    try self.cache.put(size, atlas);

    return atlas;
}

pub const GlyphInfo = struct {
    uv: Vec4f,
    size: Vec2i, // glyph bitmap size
    bearing: Vec2i, // left/top offsets
    advance: i32, // advance.x (in 1/64 pixels)

};

pub const FontAtlas = struct {
    // For now we always give the one pointer to the same font face
    // later we need a cache for the fontFace and a separate one for the size
    fontFace: *freetype.FT_FaceRec,
    texture: *sdl.SDL_Texture,
    glyphs: std.AutoHashMapUnmanaged(u32, GlyphInfo),
    nextX: i32,
    nextY: i32,
    rowHeight: i32,

    fontSize: i32,
    width: f32,
    height: f32,
    baseline: f32,

    pub fn getGlyph(atlas: *FontAtlas, allocator: std.mem.Allocator, codepoint: u32) !GlyphInfo {
        if (atlas.glyphs.get(codepoint)) |info| return info;

        const err = freetype.FT_Load_Char(atlas.fontFace, codepoint, freetype.FT_LOAD_RENDER);
        if (err != 0) return error.FreetypeLoadError;

        const slot = atlas.fontFace.*.glyph;
        const bmp = slot.*.bitmap;

        // Pack into atlas
        if (atlas.nextX + @as(i32, @intCast(bmp.width)) > 1024) {
            atlas.nextX = 0;
            atlas.nextY += atlas.rowHeight;
            atlas.rowHeight = 0;
        }

        const dst_rect: sdl.SDL_Rect = .{
            .x = atlas.nextX,
            .y = atlas.nextY,
            .w = @intCast(bmp.width),
            .h = @intCast(bmp.rows),
        };

        const glyph_buffer_size: usize = @as(usize, @intCast(bmp.width)) * @as(usize, @intCast(bmp.rows)) * 4;
        var glyph_buffer = try allocator.alloc(u8, glyph_buffer_size);
        defer allocator.free(glyph_buffer);

        for (0..@as(usize, @as(usize, @intCast(bmp.rows)))) |y| {
            for (0..@as(usize, @as(usize, @intCast(bmp.width)))) |x| {
                const gray_value = bmp.buffer[y * @as(usize, @intCast(bmp.pitch)) + x];
                const rgba_offset = (y * @as(usize, @intCast(bmp.width)) + x) * 4;
                glyph_buffer[rgba_offset] = gray_value; // R
                glyph_buffer[rgba_offset + 1] = gray_value; // G
                glyph_buffer[rgba_offset + 2] = gray_value; // B
                glyph_buffer[rgba_offset + 3] = gray_value; // A
            }
        }

        _ = sdl.SDL_UpdateTexture(
            atlas.texture,
            &dst_rect,
            @ptrCast(glyph_buffer),
            @as(c_int, @intCast(bmp.width)) * 4,
        );

        const uv: Vec4f = .{
            @as(f32, @floatFromInt(dst_rect.x)) / 1024.0,
            @as(f32, @floatFromInt(dst_rect.y)) / 1024.0,
            @as(f32, @floatFromInt(dst_rect.x + dst_rect.w)) / 1024.0,
            @as(f32, @floatFromInt(dst_rect.y + dst_rect.h)) / 1024.0,
        };

        const info: GlyphInfo = .{
            .uv = uv,
            .size = .{ @intCast(bmp.width), @intCast(bmp.rows) },
            .bearing = .{ slot.*.bitmap_left, slot.*.bitmap_top },
            .advance = @intCast(slot.*.advance.x),
        };
        try atlas.glyphs.put(allocator, codepoint, info);

        atlas.nextX += @intCast(bmp.width);
        if (bmp.rows > atlas.rowHeight) atlas.rowHeight = @intCast(bmp.rows);

        return info;
    }
};
