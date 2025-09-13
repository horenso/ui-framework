const std = @import("std");
const sdl = @import("sdl.zig").sdl;

const vec = @import("vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const Vec2i = vec.Vec2i;

const FontAtlas = @import("FontManager.zig").FontAtlas;

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn init(r: u8, g: u8, b: u8, a: u8) @This() {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    inline fn toSdl(self: @This()) sdl.SDL_Color {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = self.a };
    }
};

pub const RectI = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    inline fn toSdl(self: @This()) sdl.SDL_Rect {
        return .{
            .x = @intCast(self.x),
            .y = @intCast(self.y),
            .w = @intCast(self.w),
            .h = @intCast(self.h),
        };
    }
};

pub const RectF = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    inline fn toSdl(self: @This()) sdl.SDL_Rect {
        return .{
            .x = self.x,
            .y = self.y,
            .w = self.w,
            .h = self.h,
        };
    }
};

pub const Texture = struct { sdlTexture: *sdl.SDL_Texture };

sdlRenderer: *sdl.SDL_Renderer,

checkerTexture: *sdl.SDL_Texture,

offset: Vec2f = .{ 0, 0 },

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

pub fn fillRect(self: @This(), rect: RectF, color: Color) void {
    _ = sdl.SDL_SetRenderDrawColor(
        @ptrCast(self.sdlRenderer),
        color.r,
        color.g,
        color.b,
        color.a,
    );
    _ = sdl.SDL_RenderFillRect(@ptrCast(self.sdlRenderer), &.{
        .x = rect.x + self.offset[0],
        .y = rect.y + self.offset[1],
        .w = rect.w,
        .h = rect.h,
    });
}

pub fn fillRectPattern(self: *@This(), rect: RectF) void {
    _ = sdl.SDL_RenderTextureTiled(
        self.sdlRenderer,
        self.checkerTexture,
        null,
        1.0,
        &.{
            .x = rect.x + self.offset[0],
            .y = rect.y + self.offset[1],
            .w = rect.w,
            .h = rect.h,
        },
    );
}

pub fn line(self: @This(), p1: Vec2f, p2: Vec2f, color: Color) void {
    _ = sdl.SDL_SetRenderDrawColor(
        @ptrCast(self.sdlRenderer),
        color.r,
        color.g,
        color.b,
        color.a,
    );
    _ = sdl.SDL_RenderLine(
        @ptrCast(self.sdlRenderer),
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
        .x = self.offset[0] + pos[0] + @as(f32, @floatFromInt(glyph.bearing[0])),
        .y = self.offset[1] + pos[1] + fontAtlas.height - @as(f32, @floatFromInt(glyph.bearing[1])) + fontAtlas.baseline,
        .w = @floatFromInt(glyph.size[0]),
        .h = @floatFromInt(glyph.size[1]),
    };

    if (!sdl.SDL_SetTextureColorMod(fontAtlas.texture, color.r, color.g, color.b)) @panic("unexpected");
    if (!sdl.SDL_RenderTexture(@ptrCast(self.sdlRenderer), fontAtlas.texture, &src_rect, &dst_rect)) @panic("unexpected");
    if (!sdl.SDL_SetTextureColorMod(fontAtlas.texture, 255, 255, 255)) @panic("unexpected");
}
