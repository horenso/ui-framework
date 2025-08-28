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

pub fn layout(opaquePtr: *const anyopaque, size: Vec2f) void {
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    self.child.layout(size);
}

pub fn draw(opaquePtr: *const anyopaque, app: *Application, size: Vec2f, position: Vec2f, offset: Vec2f) !void {
    _ = app;
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    try self.child.draw(position, offset + self.offset);

    // Vertical Scrollbar
    const contentSize = self.child.getMaxContentSize();
    if (contentSize[1] > size[1]) {
        rl.drawRectangleV(
            .{ .x = size[0] - SCROLLBAR_SIZE, .y = 0 },
            .{ .x = SCROLLBAR_SIZE, .y = size[1] },
            .{ .r = 200, .g = 200, .b = 0, .a = 60 },
        );

        const ratio = self.size[1] / contentSize[1];
        const scrolled = -self.offset[1] / contentSize[1];

        const p = rl.Vector2{ .x = size[0] - SCROLLBAR_SIZE, .y = self.size[1] * scrolled };
        const s = rl.Vector2{ .x = SCROLLBAR_SIZE, .y = size[1] * ratio };
        rl.drawRectangleV(
            p,
            s,
            .red,
        );
    }
    // Horizontal Scrollbar
    if (contentSize[0] > self.size[0]) {
        rl.drawRectangleV(
            .{ .x = self.size[0], .y = self.size[1] + SCROLLBAR_SIZE },
            .{ .x = self.size[0], .y = SCROLLBAR_SIZE },
            .{ .r = 200, .g = 200, .b = 0, .a = 60 },
        );

        const ratio = self.size[0] / contentSize[0];
        const scrolled = -self.offset[0] / contentSize[0];

        const p = rl.Vector2{ .x = self.size[0] * scrolled, .y = self.size[1] - SCROLLBAR_SIZE };
        const s = rl.Vector2{ .x = self.size[0] * ratio, .y = SCROLLBAR_SIZE };
        rl.drawRectangleV(
            p,
            s,
            .blue,
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
            const childSize = self.child.getMaxContentSize();
            const newOffsetX = self.offset[0] + mouseWheelMove[0] * SCROLL_SPEED;
            const newOffsetY = self.offset[1] + mouseWheelMove[1] * SCROLL_SPEED;
            self.offset = .{
                std.math.clamp(newOffsetX, 0, childSize[0]),
                std.math.clamp(newOffsetY, -childSize[1], 0),
            };

            std.log.debug(
                "Offset updated from ({d}, {d}) to ({d}, {d}) after clamping. " ++
                    "Initial new values were ({d}, {d}). Child size is ({d}, {d})",
                .{
                    self.offset[0] - (newOffsetX - std.math.clamp(newOffsetX, 0, childSize[0])),
                    self.offset[1] - (newOffsetY - std.math.clamp(newOffsetY, -childSize[1], 0)),
                    self.offset[0],
                    self.offset[1],
                    newOffsetX,
                    newOffsetY,
                    childSize[0],
                    childSize[1],
                },
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
