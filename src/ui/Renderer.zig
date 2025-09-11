const std = @import("std");
const sdl = @import("sdl.zig").sdl;

const vec = @import("vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const Vec2i = vec.Vec2i;

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn init(r: u8, g: u8, b: u8, a: u8) @This() {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    inline fn toSdl(comptime color: @This()) sdl.SDL_Color {
        return .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
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

pub fn init(sdlRenderer: *sdl.SDL_Renderer) @This() {
    _ = sdl.SDL_RenderClear(sdlRenderer);
    return .{ .sdlRenderer = sdlRenderer };
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
        .x = rect.x,
        .y = rect.y,
        .w = rect.w,
        .h = rect.h,
    });
}

pub fn line(self: @This(), p1: Vec2f, p2: Vec2f, color: Color) void {
    _ = sdl.SDL_SetRenderDrawColor(
        @ptrCast(self.sdlRenderer),
        color.r,
        color.g,
        color.b,
        color.a,
    );
    _ = sdl.SDL_RenderLine(@ptrCast(self.sdlRenderer), p1[0], p1[1], p2[0], p2[1]);
}

pub fn createTexture(self: @This()) Texture {
    const sdlTexture = sdl.SDL_CreateTexture(
        self.sdlRenderer,
        sdl.SDL_PIXELFORMAT_RGBA32,
        sdl.SDL_TEXTUREACCESS_STREAMING,
        1024,
        1024,
    ) orelse unreachable;
    return .{ .sdlTexture = sdlTexture };
}
