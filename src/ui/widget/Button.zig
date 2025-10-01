const std = @import("std");

const sdl = @import("../sdl.zig").sdl;

const Application = @import("../Application.zig");
const Color = @import("../Color.zig");
const Event = @import("../event.zig").Event;
const Renderer = @import("../Renderer.zig");
const Widget = @import("./Widget.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;

text: []const u8,

pub fn init(text: []const u8) @This() {
    return .{ .text = text };
}

pub fn deinit(opaquePtr: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    _ = self;
}

pub fn handleHover(opaquePtr: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    _ = self;
}

pub fn layout(opaquePtr: *anyopaque, size: Vec2f) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    _ = self;
    _ = size;
}

pub fn draw(opaquePtr: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    _ = self;
    _ = renderer;
}

pub fn handleEvent(opaquePtr: *anyopaque, event: Event) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    _ = self;
    _ = event;
}

pub fn getMaxContentSize(opaquePtr: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    _ = self;
}

pub fn widget(self: *@This()) Widget {
    return .{
        .ptr = self,
        .vtable = &.{
            .deinit = deinit,
            .handleHover = handleHover,
            .layout = layout,
            .draw = draw,
            .handleEvent = handleEvent,
            .getMaxContentSize = getMaxContentSize,
        },
    };
}
