const std = @import("std");
const rl = @import("raylib");

const Application = @import("../Application.zig");
const Event = @import("../event.zig").Event;
const Widget = @import("./Widget.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;

const SCROLL_SPEED = 40.0;
const SCROLLBAR_SIZE = 20;

offset: Vec2f = .{ 0, 0 },
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

pub fn getMaxContentSize(opaquePtr: *const anyopaque) Vec2f {
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    return self.child.getMaxContentSize();
}

pub fn draw(opaquePtr: *const anyopaque, app: *Application, position: Vec2f, size: Vec2f, offset: Vec2f) !void {
    _ = app;
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    try self.child.draw(position, size, offset + self.offset);

    // Vertical Scrollbar
    const contentSize = self.child.getMaxContentSize();
    if (contentSize[1] > size[1]) {
        rl.drawRectangleV(
            .{ .x = size[0] - SCROLLBAR_SIZE, .y = 0 },
            .{ .x = SCROLLBAR_SIZE, .y = size[1] },
            .{ .r = 200, .g = 200, .b = 0, .a = 60 },
        );

        const ratio = contentSize[1] / size[1];

        const p = rl.Vector2{ .x = size[0] - SCROLLBAR_SIZE, .y = self.offset[1] };
        const s = rl.Vector2{ .x = SCROLLBAR_SIZE, .y = ratio };
        std.log.debug("{any} {any} {any}", .{ p, s, ratio });
        rl.drawRectangleV(
            p,
            s,
            .red,
        );
    }
}

pub fn handleEvent(opaquePtr: *anyopaque, _: *Application, event: Event) !bool {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));

    const e = if (event == .clickEvent) blk: {
        var newClickEvent = event;
        newClickEvent.clickEvent.x -= @intFromFloat(self.offset[0]);
        newClickEvent.clickEvent.y -= @intFromFloat(self.offset[1]);
        break :blk newClickEvent;
    } else event;
    const childHandledEvent = try self.child.handleEvent(e);
    if (childHandledEvent) {
        return true;
    }
    switch (event) {
        .mouseWheelEvent => |mouseWheelMove| {
            self.offset = .{
                self.offset[0] + mouseWheelMove[0] * SCROLL_SPEED,
                self.offset[1] + mouseWheelMove[1] * SCROLL_SPEED,
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
            .getMaxContentSize = getMaxContentSize,
        },
    };
}
