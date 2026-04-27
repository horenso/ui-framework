const std = @import("std");

const sdl = @import("sdl");

const Application = @import("../Application.zig");
const Color = @import("../Color.zig");
const Event = @import("../event.zig").Event;
const Renderer = @import("../rendering/Renderer.zig");
const Widget = @import("Widget.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;

text: []const u8,

pub fn init(text: []const u8) @This() {
    return .{ .text = text };
}

pub fn deinitImpl(opaquePtr: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    _ = self;
}

pub fn handleHoverImpl(opaquePtr: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    _ = self;
}

pub fn layoutImpl(opaquePtr: *anyopaque, size: Vec2f) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    _ = self;
    _ = size;
}

pub fn drawImpl(opaquePtr: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    _ = self;
    _ = renderer;
}

pub fn handleEventImpl(opaquePtr: *anyopaque, event: Event) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    _ = self;
    _ = event;
}

pub fn getMaxContentSizeImpl(opaquePtr: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    _ = self;
}

pub fn widget(self: *@This()) Widget {
    return .{
        .ptr = self,
        .vtable = &.{
            .deinit = deinitImpl,
            .handleHover = handleHoverImpl,
            .layout = layoutImpl,
            .draw = drawImpl,
            .handleEvent = handleEventImpl,
            .getMaxContentSize = getMaxContentSizeImpl,
        },
    };
}
