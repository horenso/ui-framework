const std = @import("std");

const sdl = @import("sdl");

const freetype = @import("freetype");

const vec = @import("./vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const Vec2i = vec.Vec2i;

const Key = i32;
const Renderer = @import("Renderer.zig");

const FONT_PATH = "res/VictorMonoAll/VictorMono-Medium.ttf";
const ATLAS_SIZE = Renderer.ATLAS_SIZE;

library: freetype.FT_Library,
fontFace: *freetype.FT_FaceRec,
cache: std.AutoArrayHashMapUnmanaged(Key, *FontAtlas),

pub fn init() !@This() {
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
        .cache = .{},
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    for (self.cache.values()) |fontAtlas| {
        fontAtlas.glyphs.deinit(allocator);
        allocator.free(fontAtlas.cpuPixels);
        // GPU resources are released by the Renderer when the device is destroyed.
        allocator.destroy(fontAtlas);
    }
    self.cache.deinit(allocator);

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

    _ = freetype.FT_Set_Pixel_Sizes(self.fontFace, 0, @intCast(size));

    const metrics = self.fontFace.*.size.*.metrics;

    const width: f32 = @floatFromInt(metrics.max_advance >> 6);
    const height: f32 = @floatFromInt(metrics.height >> 6);
    const baseline: f32 = @floatFromInt(metrics.descender >> 6);

    const texture = renderer.createTexture().sdlTexture;

    const transferInfo: sdl.SDL_GPUTransferBufferCreateInfo = .{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = ATLAS_SIZE * ATLAS_SIZE,
    };
    const transferBuffer = sdl.SDL_CreateGPUTransferBuffer(renderer.device, &transferInfo) orelse return error.SDLError;

    const cpuPixels = try allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE);
    @memset(cpuPixels, 0);

    const atlas = try allocator.create(FontAtlas);
    atlas.* = .{
        .fontFace = self.fontFace,
        .texture = texture,
        .transferBuffer = transferBuffer,
        .cpuPixels = cpuPixels,
        .glyphs = .empty,
        .nextX = 0,
        .nextY = 0,
        .rowHeight = 0,
        .fontSize = size,
        .width = width,
        .height = height,
        .baseline = baseline,
        .dirty = false,
    };
    try self.cache.put(allocator, size, atlas);

    return atlas;
}

pub const GlyphInfo = struct {
    /// Normalized UV rectangle: { u0, v0, u1, v1 }.
    uv: Vec4f,
    size: Vec2i,
    bearing: Vec2i,
    advance: i32,
};

pub const FontAtlas = struct {
    fontFace: *freetype.FT_FaceRec,
    texture: *sdl.SDL_GPUTexture,
    transferBuffer: *sdl.SDL_GPUTransferBuffer,
    cpuPixels: []u8,
    glyphs: std.AutoHashMapUnmanaged(u32, GlyphInfo),
    nextX: i32,
    nextY: i32,
    rowHeight: i32,

    fontSize: i32,
    width: f32,
    height: f32,
    baseline: f32,

    /// True if cpuPixels was modified since the last GPU upload.
    dirty: bool,

    pub fn getGlyph(atlas: *FontAtlas, allocator: std.mem.Allocator, codepoint: u32) !GlyphInfo {
        if (atlas.glyphs.get(codepoint)) |info| return info;

        // FreeType state is per-face and may have been left configured for a different size
        // (e.g. when a previous atlas of a different size was used most recently). Re-set it.
        _ = freetype.FT_Set_Pixel_Sizes(atlas.fontFace, 0, @intCast(atlas.fontSize));

        const err = freetype.FT_Load_Char(atlas.fontFace, codepoint, freetype.FT_LOAD_RENDER);
        if (err != 0) return error.FreetypeLoadError;

        const slot = atlas.fontFace.*.glyph;
        const bmp = slot.*.bitmap;

        if (atlas.nextX + @as(i32, @intCast(bmp.width)) > ATLAS_SIZE) {
            atlas.nextX = 0;
            atlas.nextY += atlas.rowHeight;
            atlas.rowHeight = 0;
        }

        const dst_x: i32 = atlas.nextX;
        const dst_y: i32 = atlas.nextY;
        const w_u: usize = @intCast(bmp.width);
        const h_u: usize = @intCast(bmp.rows);
        const pitch_u: usize = @intCast(@abs(bmp.pitch));

        for (0..h_u) |y| {
            const src_row_off = y * pitch_u;
            const dst_row_off = (@as(usize, @intCast(dst_y)) + y) * ATLAS_SIZE + @as(usize, @intCast(dst_x));
            for (0..w_u) |x| {
                atlas.cpuPixels[dst_row_off + x] = bmp.buffer[src_row_off + x];
            }
        }

        const uv: Vec4f = .{
            @as(f32, @floatFromInt(dst_x)) / @as(f32, @floatFromInt(ATLAS_SIZE)),
            @as(f32, @floatFromInt(dst_y)) / @as(f32, @floatFromInt(ATLAS_SIZE)),
            @as(f32, @floatFromInt(dst_x + @as(i32, @intCast(bmp.width)))) / @as(f32, @floatFromInt(ATLAS_SIZE)),
            @as(f32, @floatFromInt(dst_y + @as(i32, @intCast(bmp.rows)))) / @as(f32, @floatFromInt(ATLAS_SIZE)),
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

        atlas.dirty = true;
        return info;
    }
};
