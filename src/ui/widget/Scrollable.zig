const std = @import("std");
const rl = @import("raylib");

const Application = @import("../Application.zig");
const Event = @import("../event.zig").Event;
const Widget = @import("./Widget.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;

const Scrollbar = struct {
    visible: bool,
    length: f32,
    thumbPos: f32,
    thumbLength: f32,
};

const SCROLL_SPEED = 40.0;
const SCROLL_SPEED_VEC: Vec2f = @splat(SCROLL_SPEED);
const SCROLLBAR_SIZE = 20;

const SCROLLBAR_BACKGROUND_COLOR = rl.Color.init(0, 0, 0, 40);
const SCROLLBAR_FOREGROUND_COLOR = rl.Color.init(0, 0, 0, 100);

offset: Vec2f = .{ 0, 0 },
child: Widget,

scrollbarX: Scrollbar = .{
    .visible = false,
    .length = 0,
    .thumbPos = 0,
    .thumbLength = 0,
},
scrollbarY: Scrollbar = .{
    .visible = false,
    .length = 0,
    .thumbPos = 0,
    .thumbLength = 0,
},

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

    const contentSize = self.child.getMaxContentSize();
    self.setAndClampOffset(size, self.child.getMaxContentSize(), self.offset);

    self.scrollbarX.visible = contentSize[0] > size[0];
    self.scrollbarY.visible = contentSize[1] > size[1];

    if (self.scrollbarX.visible) {
        const spaceForOtherScrollbar: f32 = if (self.scrollbarY.visible) SCROLLBAR_SIZE else 0;
        self.scrollbarX.length = size[0] - spaceForOtherScrollbar;

        const ratio = (size[0] - spaceForOtherScrollbar) / contentSize[0];
        self.scrollbarX.thumbLength = self.scrollbarX.length * ratio;

        const scrolled = -self.offset[0] / (contentSize[0] - self.scrollbarX.length);
        self.scrollbarX.thumbPos = (self.scrollbarX.length - self.scrollbarX.thumbLength) * scrolled;
    }

    if (self.scrollbarY.visible) {
        const spaceForOtherScrollbar: f32 = if (self.scrollbarX.visible) SCROLLBAR_SIZE else 0;
        self.scrollbarY.length = size[1] - spaceForOtherScrollbar;

        const ratio = (size[1] - spaceForOtherScrollbar) / contentSize[1];
        self.scrollbarY.thumbLength = self.scrollbarY.length * ratio;

        const scrolled = -self.offset[1] / (contentSize[1] - self.scrollbarY.length);
        self.scrollbarY.thumbPos = (self.scrollbarY.length - self.scrollbarY.thumbLength) * scrolled;
    }
}

pub fn draw(opaquePtr: *const anyopaque, size: Vec2f, offset: Vec2f) !void {
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    try self.child.draw(offset + self.offset);

    if (self.scrollbarY.visible) {
        rl.drawRectangleV(
            .{ .x = size[0] - SCROLLBAR_SIZE, .y = 0 },
            .{ .x = SCROLLBAR_SIZE, .y = self.scrollbarY.length },
            SCROLLBAR_BACKGROUND_COLOR,
        );
        rl.drawRectangleV(
            .{ .x = size[0] - SCROLLBAR_SIZE, .y = self.scrollbarY.thumbPos },
            .{ .x = SCROLLBAR_SIZE, .y = self.scrollbarY.thumbLength },
            SCROLLBAR_FOREGROUND_COLOR,
        );
    }

    if (self.scrollbarX.visible) {
        rl.drawRectangleV(
            .{ .x = 0, .y = size[1] - SCROLLBAR_SIZE },
            .{ .x = self.scrollbarX.length, .y = SCROLLBAR_SIZE },
            SCROLLBAR_BACKGROUND_COLOR,
        );
        rl.drawRectangleV(
            .{ .x = self.scrollbarX.thumbPos, .y = size[1] - SCROLLBAR_SIZE },
            .{ .x = self.scrollbarX.thumbLength, .y = SCROLLBAR_SIZE },
            SCROLLBAR_FOREGROUND_COLOR,
        );
    }
}

fn setAndClampOffset(self: *@This(), size: Vec2f, contentSize: Vec2f, newOffset: Vec2f) void {
    const lower: Vec2f = .{
        @min(0, size[0] - contentSize[0] - SCROLLBAR_SIZE),
        @min(0, size[1] - contentSize[1] - SCROLLBAR_SIZE),
    };
    self.offset = .{
        std.math.clamp(newOffset[0], lower[0], 0),
        std.math.clamp(newOffset[1], lower[1], 0),
    };
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
            const contentSize = self.child.getMaxContentSize();

            const canScrollX = contentSize[0] > size[0];
            const canScrollY = contentSize[1] > size[1];

            var newOffset = self.offset;
            if (canScrollX) {
                newOffset[0] = self.offset[0] + mouseWheelMove[0] * SCROLL_SPEED;
            }
            if (canScrollY) {
                newOffset[1] = self.offset[1] + mouseWheelMove[1] * SCROLL_SPEED;
            }
            self.setAndClampOffset(size, contentSize, newOffset);

            return canScrollX or canScrollY;
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
