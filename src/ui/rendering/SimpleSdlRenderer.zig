const std = @import("std");
const sdl = @import("sdl");

const Renderer = @import("Renderer.zig");
const Color = @import("../Color.zig");
const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const FontAtlas = @import("../FontManager.zig").FontAtlas;

const DEBUG_DISABLE_CLIPPING = true;

sdlRenderer: *sdl.SDL_Renderer,
checkerTexture: *sdl.SDL_Texture,

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

pub fn renderer(self: *@This()) Renderer {
    return .{
        .ptr = self,
        .vtable = &vtable,
    };
}

const vtable: Renderer.VTable = .{
    .deinit = deinitImpl,
    .setClip = setClipImpl,
    .clear = clearImpl,
    .present = presentImpl,
    .outline = outlineImpl,
    .fillRect = fillRectImpl,
    .fillRectPattern = fillRectPatternImpl,
    .line = lineImpl,
    .createTexture = createTextureImpl,
    .drawCharacter = drawCharacterImpl,
};

fn deinitImpl(ptr: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    self.deinit();
}

fn setClipImpl(ptr: *anyopaque, offset: Vec2f, clip: Vec2f) void {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    if (DEBUG_DISABLE_CLIPPING) return;
    if (!sdl.SDL_SetRenderClipRect(self.sdlRenderer, &.{
        .x = @intFromFloat(offset[0]),
        .y = @intFromFloat(offset[1]),
        .w = @intFromFloat(clip[0]),
        .h = @intFromFloat(clip[1]),
    })) {
        std.log.warn("Could not set renderer clip: {s}", .{sdl.SDL_GetError()});
    }
}

fn clearImpl(ptr: *anyopaque, color: Color) void {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    _ = sdl.SDL_SetRenderDrawColor(self.sdlRenderer, color.r, color.g, color.b, color.a);
    _ = sdl.SDL_RenderClear(self.sdlRenderer);
}

fn presentImpl(ptr: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    _ = sdl.SDL_RenderPresent(self.sdlRenderer);
}

fn outlineImpl(ptr: *anyopaque, rect: Vec4f, offset: Vec2f, color: Color) void {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    _ = sdl.SDL_SetRenderDrawColor(self.sdlRenderer, color.r, color.g, color.b, color.a);
    _ = sdl.SDL_RenderRect(self.sdlRenderer, &.{
        .x = rect[0] + offset[0],
        .y = rect[1] + offset[1],
        .w = rect[2],
        .h = rect[3],
    });
}

fn fillRectImpl(ptr: *anyopaque, rect: Vec4f, offset: Vec2f, color: Color) void {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    _ = sdl.SDL_SetRenderDrawColor(self.sdlRenderer, color.r, color.g, color.b, color.a);
    _ = sdl.SDL_RenderFillRect(self.sdlRenderer, &.{
        .x = rect[0] + offset[0],
        .y = rect[1] + offset[1],
        .w = rect[2],
        .h = rect[3],
    });
}

fn fillRectPatternImpl(ptr: *anyopaque, rect: Vec4f, offset: Vec2f) void {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    _ = sdl.SDL_RenderTextureTiled(
        self.sdlRenderer,
        self.checkerTexture,
        null,
        1.0,
        &.{
            .x = rect[0] + offset[0],
            .y = rect[1] + offset[1],
            .w = rect[2],
            .h = rect[3],
        },
    );
}

fn lineImpl(ptr: *anyopaque, p1: Vec2f, p2: Vec2f, offset: Vec2f, color: Color) void {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    _ = sdl.SDL_SetRenderDrawColor(self.sdlRenderer, color.r, color.g, color.b, color.a);
    _ = sdl.SDL_RenderLine(
        self.sdlRenderer,
        p1[0] + offset[0],
        p1[1] + offset[1],
        p2[0] + offset[0],
        p2[1] + offset[1],
    );
}

fn createTextureImpl(ptr: *anyopaque, w: i32, h: i32) Renderer.Texture {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    const sdlTexture = sdl.SDL_CreateTexture(
        self.sdlRenderer,
        sdl.SDL_PIXELFORMAT_RGBA32,
        sdl.SDL_TEXTUREACCESS_STREAMING,
        w,
        h,
    ) orelse @panic("unexpected");
    return sdlTexture;
}

fn drawCharacterImpl(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    codepoint: u32,
    fontAtlasPtr: *anyopaque,
    pos: Vec2f,
    offset: Vec2f,
    color: Color,
) void {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    const fontAtlas: *FontAtlas = @ptrCast(@alignCast(fontAtlasPtr));

    const glyph = fontAtlas.getGlyph(allocator, codepoint) catch @panic("unexpected");

    const tex_size: f32 = 1024;
    const src_rect: sdl.SDL_FRect = .{
        .x = glyph.uv[0] * tex_size,
        .y = glyph.uv[1] * tex_size,
        .w = @floatFromInt(glyph.size[0]),
        .h = @floatFromInt(glyph.size[1]),
    };

    const dst_rect: sdl.SDL_FRect = .{
        .x = @round(offset[0] + pos[0] + @as(f32, @floatFromInt(glyph.bearing[0]))),
        .y = @round(offset[1] + pos[1] + fontAtlas.height - @as(f32, @floatFromInt(glyph.bearing[1])) + fontAtlas.baseline),
        .w = @floatFromInt(glyph.size[0]),
        .h = @floatFromInt(glyph.size[1]),
    };

    const sdlTexture: *sdl.SDL_Texture = @ptrCast(@alignCast(fontAtlas.texture));
    if (!sdl.SDL_SetTextureColorMod(sdlTexture, color.r, color.g, color.b)) @panic("unexpected");
    if (!sdl.SDL_RenderTexture(self.sdlRenderer, sdlTexture, &src_rect, &dst_rect)) @panic("unexpected");
    if (!sdl.SDL_SetTextureColorMod(sdlTexture, 255, 255, 255)) @panic("unexpected");
}
