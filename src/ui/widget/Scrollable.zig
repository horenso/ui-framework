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

const SCROLLBAR_BACKGROUND_COLOR = rl.Color.init(0, 0, 0, 40);
const SCROLLBAR_FOREGROUND_COLOR = rl.Color.init(0, 0, 0, 100);

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

pub fn layout(opaquePtr: *anyopaque, size: Vec2f) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    self.child.layout(size);
}

pub fn draw(opaquePtr: *const anyopaque, app: *Application, position: Vec2f, size: Vec2f, offset: Vec2f) !void {
    _ = app;
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    try self.child.draw(position, offset + self.offset);

    // Vertical Scrollbar
    const contentSize = self.child.getMaxContentSize();
    if (contentSize[1] > size[1]) {
        const scrollbarLength = size[1] - SCROLLBAR_SIZE;
        rl.drawRectangleV(
            .{ .x = size[0] - SCROLLBAR_SIZE, .y = 0 },
            .{ .x = SCROLLBAR_SIZE, .y = scrollbarLength },
            SCROLLBAR_BACKGROUND_COLOR,
        );

        const ratio = (size[1] - SCROLLBAR_SIZE) / contentSize[1];
        const scrolled = -self.offset[1] / contentSize[1];

        rl.drawRectangleV(
            .{ .x = size[0] - SCROLLBAR_SIZE, .y = scrollbarLength * scrolled },
            .{ .x = SCROLLBAR_SIZE, .y = scrollbarLength * ratio },
            SCROLLBAR_FOREGROUND_COLOR,
        );
    }
    // Horizontal Scrollbar
    if (contentSize[0] > size[0]) {
        const scrollbarLength = size[0] - SCROLLBAR_SIZE;
        rl.drawRectangleV(
            .{ .x = 0, .y = size[1] - SCROLLBAR_SIZE },
            .{ .x = scrollbarLength, .y = SCROLLBAR_SIZE },
            SCROLLBAR_BACKGROUND_COLOR,
        );

        const ratio = (size[0] - SCROLLBAR_SIZE) / contentSize[0];
        const scrolled = -self.offset[0] / contentSize[0];

        rl.drawRectangleV(
            .{ .x = scrollbarLength * scrolled, .y = size[1] - SCROLLBAR_SIZE },
            .{ .x = scrollbarLength * ratio, .y = SCROLLBAR_SIZE },
            SCROLLBAR_FOREGROUND_COLOR,
        );
    }
}

pub fn handleEvent(opaquePtr: *anyopaque, _: *Application, event: Event, size: Vec2f) !bool {
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
            const childSize = self.child.getMaxContentSize();
            const newOffset: Vec2f = .{
                self.offset[0] + mouseWheelMove[0] * SCROLL_SPEED,
                self.offset[1] + mouseWheelMove[1] * SCROLL_SPEED,
            };
            self.offset = .{
                std.math.clamp(newOffset[0], size[0] - childSize[0] - SCROLLBAR_SIZE, 0),
                std.math.clamp(newOffset[1], size[1] - childSize[1] - SCROLLBAR_SIZE, 0),
            };

            std.log.debug(
                "Size ({d}, {d}) Content ({d}, {d}) Offset ({d}, {d})",
                .{ size[0], size[1], childSize[0], childSize[1], self.offset[0], self.offset[1] },
            );
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
            .layout = layout,
            .draw = draw,
            .handleEvent = handleEvent,
            .getMaxContentSize = getMaxContentSize,
        },
    };
}
