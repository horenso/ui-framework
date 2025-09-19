const std = @import("std");
const sdl = @import("sdl.zig").sdl;

const vecImport = @import("vec.zig");
const Vec2f = vecImport.Vec2f;
const Vec4f = vecImport.Vec4f;
const Vec2i = vecImport.Vec2i;

const Color = @import("Color.zig");
const FontAtlas = @import("FontManager.zig").FontAtlas;

fn colorToSdl(color: Color) sdl.SDL_Color {
    return .{
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = color.a,
    };
}

fn vec4fToSdlRectF(vec: Vec4f) sdl.SDL_RectF {
    return .{
        .x = vec[0],
        .y = vec[1],
        .w = vec[2],
        .h = vec[3],
    };
}

pub const Texture = struct { sdlTexture: *sdl.SDL_Texture };

sdlRenderer: *sdl.SDL_Renderer,

checkerTexture: *sdl.SDL_Texture,

offset: Vec2f = .{ 0, 0 },
_clip: Vec2f = .{ 0, 0 },

pub fn init(sdlRenderer: *sdl.SDL_Renderer) @This() {
    _ = sdl.SDL_RenderClear(sdlRenderer);

    const pixels = [16]u32{
        0xFFFFFFFF, 0xFFFFFFFF, 0xFF0000FF, 0xFF0000FF,
        0xFFFFFFFF, 0xFFFFFFFF, 0xFF0000FF, 0xFF0000FF,
        0xFF0000FF, 0xFF0000FF, 0xFFFFFFFF, 0xFFFFFFFF,
        0xFF0000FF, 0xFF0000FF, 0xFFFFFFFF, 0xFFFFFFFF,
    };

    const checkerTexture = sdl.SDL_CreateTexture(
        sdlRenderer,
        sdl.SDL_PIXELFORMAT_RGBA8888,
        sdl.SDL_TEXTUREACCESS_STATIC,
        4,
        4,
    ) orelse @panic("unexpected");

    _ = sdl.SDL_UpdateTexture(checkerTexture, null, &pixels, 4 * @sizeOf(u32));
    _ = sdl.SDL_SetTextureScaleMode(checkerTexture, sdl.SDL_SCALEMODE_NEAREST);

    return .{
        .sdlRenderer = sdlRenderer,
        .checkerTexture = checkerTexture,
    };
}

pub fn deinit(self: @This()) void {
    sdl.SDL_DestroyRenderer(self.sdlRenderer);
}

pub fn setClip(self: *@This(), clip: Vec2f) void {
    self._clip = clip;
    if (!sdl.SDL_SetRenderClipRect(self.sdlRenderer, &.{
        .x = @intFromFloat(self.offset[0]),
        .y = @intFromFloat(self.offset[1]),
        .w = @intFromFloat(self._clip[0]),
        .h = @intFromFloat(self._clip[1]),
    })) {
        std.log.warn("Could not set renderer clip: {s}", .{sdl.SDL_GetError()});
    }
}

pub fn clear(self: @This(), color: Color) void {
    _ = sdl.SDL_SetRenderDrawColor(
        self.sdlRenderer,
        color.r,
        color.g,
        color.b,
        color.a,
    );
    _ = sdl.SDL_RenderClear(self.sdlRenderer);
}

pub fn present(self: @This()) void {
    _ = sdl.SDL_RenderPresent(self.sdlRenderer);
}

pub fn outline(self: @This(), rect: Vec4f, color: Color) void {
    _ = sdl.SDL_SetRenderDrawColor(
        self.sdlRenderer,
        color.r,
        color.g,
        color.b,
        color.a,
    );
    _ = sdl.SDL_RenderRect(self.sdlRenderer, &.{
        .x = rect[0] + self.offset[0],
        .y = rect[1] + self.offset[1],
        .w = rect[2],
        .h = rect[3],
    });
}

pub fn fillRect(self: @This(), rect: Vec4f, color: Color) void {
    _ = sdl.SDL_SetRenderDrawColor(
        self.sdlRenderer,
        color.r,
        color.g,
        color.b,
        color.a,
    );
    _ = sdl.SDL_RenderFillRect(self.sdlRenderer, &.{
        .x = rect[0] + self.offset[0],
        .y = rect[1] + self.offset[1],
        .w = rect[2],
        .h = rect[3],
    });
}

pub fn fillRectPattern(self: *@This(), rect: Vec4f) void {
    _ = sdl.SDL_RenderTextureTiled(
        self.sdlRenderer,
        self.checkerTexture,
        null,
        1.0,
        &.{
            .x = rect[0] + self.offset[0],
            .y = rect[1] + self.offset[1],
            .w = rect[2],
            .h = rect[3],
        },
    );
}

pub fn line(self: @This(), p1: Vec2f, p2: Vec2f, color: Color) void {
    _ = sdl.SDL_SetRenderDrawColor(
        self.sdlRenderer,
        color.r,
        color.g,
        color.b,
        color.a,
    );
    _ = sdl.SDL_RenderLine(
        self.sdlRenderer,
        p1[0] + self.offset[0],
        p1[1] + self.offset[1],
        p2[0] + self.offset[0],
        p2[1] + self.offset[1],
    );
}

pub fn createTexture(self: @This()) Texture {
    const sdlTexture = sdl.SDL_CreateTexture(
        self.sdlRenderer,
        sdl.SDL_PIXELFORMAT_RGBA32,
        sdl.SDL_TEXTUREACCESS_STREAMING,
        1024,
        1024,
    ) orelse @panic("unexpected");
    return .{ .sdlTexture = sdlTexture };
}

pub fn drawCharacter(
    self: @This(),
    allocator: std.mem.Allocator,
    codepoint: u32,
    fontAtlas: *FontAtlas,
    pos: Vec2f,
    color: Color,
) void {
    // TODO error handling
    const glyph = fontAtlas.getGlyph(allocator, codepoint) catch @panic("unexpected");

    const tex_size: f32 = 1024;
    const src_rect: sdl.SDL_FRect = .{
        .x = glyph.uv[0] * tex_size,
        .y = (glyph.uv[1] * tex_size),
        .w = @floatFromInt(glyph.size[0]),
        .h = @floatFromInt(glyph.size[1]),
    };

    const dst_rect: sdl.SDL_FRect = .{
        .x = @round(self.offset[0] + pos[0] + @as(f32, @floatFromInt(glyph.bearing[0]))),
        .y = @round(self.offset[1] + pos[1] + fontAtlas.height - @as(f32, @floatFromInt(glyph.bearing[1])) + fontAtlas.baseline),
        .w = @floatFromInt(glyph.size[0]),
        .h = @floatFromInt(glyph.size[1]),
    };

    if (!sdl.SDL_SetTextureColorMod(fontAtlas.texture, color.r, color.g, color.b)) @panic("unexpected");
    if (!sdl.SDL_RenderTexture(self.sdlRenderer, fontAtlas.texture, &src_rect, &dst_rect)) @panic("unexpected");
    if (!sdl.SDL_SetTextureColorMod(fontAtlas.texture, 255, 255, 255)) @panic("unexpected");
}
