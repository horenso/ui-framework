const std = @import("std");

const sdl = @import("../sdl.zig").sdl;

const Application = @import("../Application.zig");
const Color = @import("../Color.zig");
const Event = @import("../event.zig").Event;
const Renderer = @import("../Renderer.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const Vec2i = vec.Vec2i;

ptr: *anyopaque,
vtable: *const VTable,

pub const Base = struct {
    app: *Application,
    size: Vec2f = .{ 0, 0 },
};

pub const VTable = struct {
    deinit: *const fn (*anyopaque) void,
    layout: *const fn (*anyopaque, size: Vec2f) void,
    draw: *const fn (*const anyopaque, renderer: *Renderer) anyerror!void,
    /// Returns true if the event was handled, false otherwise.
    handleEvent: *const fn (*anyopaque, event: Event) anyerror!bool,
    getMaxContentSize: *const fn (*const anyopaque) Vec2f,

    getSize: *const fn (*const anyopaque) Vec2f,
};

pub fn deinit(self: @This()) void {
    self.vtable.deinit(self.ptr);
}

pub fn getMaxContentSize(self: @This()) Vec2f {
    return self.vtable.getMaxContentSize(self.ptr);
}

pub fn layout(self: @This(), size: Vec2f) void {
    return self.vtable.layout(self.ptr, size);
}

pub fn draw(self: @This(), renderer: *Renderer) anyerror!void {
    const size = self.getSize();

    _ = size;
    // TODO: do clipping
    // var rect: sdl.SDL_Rect = .{
    //     .x = 0,
    //     .y = 0,
    //     .w = @intFromFloat(size[0]),
    //     .h = @intFromFloat(size[1]),
    // };

    // if (sdl.SDL_SetRenderClipRect(@ptrCast(self), &rect) < 0) {
    //     return error.SDL;
    // }
    // defer sdl.SDL_SetRenderClipRect(@ptrCast(self.renderer), null);

    try self.vtable.draw(self.ptr, renderer);
}

pub fn handleEvent(self: @This(), event: Event) anyerror!bool {
    return self.vtable.handleEvent(self.ptr, event);
}

pub fn getSize(self: @This()) Vec2f {
    return self.vtable.getSize(self.ptr);
}
