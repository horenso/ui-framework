const std = @import("std");
const rl = @import("raylib");

const Application = @import("../Application.zig");
const Event = @import("../event.zig").Event;
const Widget = @import("./Widget.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const Vec2i = vec.Vec2i;

const SCROLL_SPEED = 40.0;

offset: Vec2i = .{ 0, 0 },
child: Widget,

pub fn init(child: Widget) @This() {
    return .{
        .child = child,
        .offset = .{ 0, 0 },
    };
}

pub fn deinit(opaquePtr: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    self.child.deinit();
}

pub fn draw(opaquePtr: *const anyopaque, app: *Application, position: Vec2f, size: Vec2f, offset: Vec2i) !void {
    _ = app;
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    try self.child.draw(position, size, offset + self.offset);
}

pub fn handleEvent(opaquePtr: *anyopaque, _: *Application, event: Event) !bool {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));

    const e = if (event == .clickEvent) blk: {
        var newClickEvent = event;
        newClickEvent.clickEvent.x -= @intCast(@abs(self.offset[0]));
        newClickEvent.clickEvent.y -= @intCast(@abs(self.offset[1]));
        break :blk newClickEvent;
    } else event;
    const childHandledEvent = try self.child.handleEvent(e);
    if (childHandledEvent) {
        return true;
    }
    switch (event) {
        .mouseWheelEvent => |mouseWheelMove| {
            self.offset = .{
                self.offset[0] + @as(i32, @intFromFloat(mouseWheelMove[0] * SCROLL_SPEED)),
                self.offset[1] + @as(i32, @intFromFloat(mouseWheelMove[1] * SCROLL_SPEED)),
            };
            return true;
        },
        else => return true,
    }
}

pub fn widget(self: *@This(), app: *Application) Widget {
    return .{
        .app = app,
        .ptr = self,
        .vtable = &.{
            .deinit = deinit,
            .draw = draw,
            .handleEvent = handleEvent,
        },
    };
}
