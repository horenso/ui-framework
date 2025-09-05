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
const SCROLLBAR_SIZE = 16.0;

const SCROLLBAR_BACKGROUND_COLOR = rl.Color.init(0, 0, 0, 40);
const SCROLLBAR_FOREGROUND_COLOR = rl.Color.init(0, 0, 0, 200);

base: Widget.Base,
child: Widget,
offset: Vec2f = .{ 0, 0 },

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

pub fn init(app: *Application, child: Widget) @This() {
    return .{
        .base = .{ .app = app },
        .child = child,
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
    self.base.size = size;
    self.child.layout(size);

    const contentSize = self.child.getMaxContentSize();
    self.setAndClampOffset(self.child.getMaxContentSize(), self.offset);

    self.scrollbarX.visible = contentSize[0] > self.base.size[0];
    self.scrollbarY.visible = contentSize[1] > self.base.size[1];

    if (self.scrollbarX.visible) {
        const spaceForOtherScrollbar: f32 = if (self.scrollbarY.visible) SCROLLBAR_SIZE else 0;
        self.scrollbarX.length = self.base.size[0] - spaceForOtherScrollbar;

        const ratio = (self.base.size[0] - spaceForOtherScrollbar) / contentSize[0];
        self.scrollbarX.thumbLength = self.scrollbarX.length * ratio;

        const scrolled = self.offset[0] / (contentSize[0] - self.scrollbarX.length);
        self.scrollbarX.thumbPos = (self.scrollbarX.length - self.scrollbarX.thumbLength) * scrolled;
    }

    if (self.scrollbarY.visible) {
        const spaceForOtherScrollbar: f32 = if (self.scrollbarX.visible) SCROLLBAR_SIZE else 0;
        self.scrollbarY.length = self.base.size[1] - spaceForOtherScrollbar;

        const ratio = (self.base.size[1] - spaceForOtherScrollbar) / contentSize[1];
        self.scrollbarY.thumbLength = self.scrollbarY.length * ratio;

        const scrolled = self.offset[1] / (contentSize[1] - self.scrollbarY.length);
        self.scrollbarY.thumbPos = (self.scrollbarY.length - self.scrollbarY.thumbLength) * scrolled;
    }
}

pub fn draw(opaquePtr: *const anyopaque) !void {
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));

    {
        const camera = rl.Camera2D{
            .offset = .{ .x = -self.offset[0], .y = -self.offset[1] },
            .target = .{ .x = 0, .y = 0 },
            .rotation = 0.0,
            .zoom = 1.0,
        };
        camera.begin();
        defer camera.end();
        try self.child.draw();
    }

    if (self.scrollbarY.visible) {
        // rl.drawRectangleV(
        //     .{ .x = self.base.size[0] - SCROLLBAR_SIZE, .y = 0 },
        //     .{ .x = SCROLLBAR_SIZE, .y = self.scrollbarY.length },
        //     SCROLLBAR_BACKGROUND_COLOR,
        // );
        rl.drawRectangleRounded(
            .{
                .x = self.base.size[0] - SCROLLBAR_SIZE,
                .y = self.scrollbarY.thumbPos,
                .width = SCROLLBAR_SIZE,
                .height = self.scrollbarY.thumbLength,
            },
            50,
            8,
            SCROLLBAR_FOREGROUND_COLOR,
        );
    }

    if (self.scrollbarX.visible) {
        // rl.drawRectangleV(
        //     .{ .x = 0, .y = self.base.size[1] - SCROLLBAR_SIZE },
        //     .{ .x = self.scrollbarX.length, .y = SCROLLBAR_SIZE },
        //     SCROLLBAR_BACKGROUND_COLOR,
        // );
        rl.drawRectangleRounded(
            .{
                .x = self.scrollbarX.thumbPos,
                .y = self.base.size[1] - SCROLLBAR_SIZE,
                .width = self.scrollbarX.thumbLength,
                .height = SCROLLBAR_SIZE,
            },
            50,
            8,
            SCROLLBAR_FOREGROUND_COLOR,
        );
    }
}

pub fn getMaxScroll(self: *@This(), size: Vec2f, contentSize: Vec2f) Vec2f {
    const upperUnbound: Vec2f = .{
        contentSize[0] - size[0] + @as(f32, if (self.scrollbarY.visible) SCROLLBAR_SIZE else 0),
        contentSize[1] - size[1] + @as(f32, if (self.scrollbarX.visible) SCROLLBAR_SIZE else 0),
    };
    return .{
        @max(0, upperUnbound[0]),
        @max(0, upperUnbound[1]),
    };
}

fn setAndClampOffset(self: *@This(), contentSize: Vec2f, newOffset: Vec2f) void {
    const upper = self.getMaxScroll(self.base.size, contentSize);
    self.offset = .{
        std.math.clamp(newOffset[0], 0, upper[0]),
        std.math.clamp(newOffset[1], 0, upper[1]),
    };
}

pub fn handleEvent(opaquePtr: *anyopaque, event: Event) !bool {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));

    const e = if (event == .clickEvent) blk: {
        var newClickEvent = event;
        newClickEvent.clickEvent.pos += self.offset;
        break :blk newClickEvent;
    } else event;
    const childHandledEvent = try self.child.handleEvent(e);
    if (childHandledEvent) {
        return true;
    }
    switch (event) {
        .mouseWheelEvent => |mouseWheelMove| {
            const contentSize = self.child.getMaxContentSize();

            const canScrollX = contentSize[0] > self.base.size[0];
            const canScrollY = contentSize[1] > self.base.size[1];

            var newOffset = self.offset;
            if (canScrollX) {
                newOffset[0] = self.offset[0] - mouseWheelMove[0] * SCROLL_SPEED;
            }
            if (canScrollY) {
                newOffset[1] = self.offset[1] - mouseWheelMove[1] * SCROLL_SPEED;
            }
            self.setAndClampOffset(contentSize, newOffset);

            return canScrollX or canScrollY;
        },
        else => return true,
    }
}

pub fn widget(self: *@This()) Widget {
    return .{
        .ptr = self,
        .vtable = &.{
            .deinit = deinit,
            .layout = layout,
            .draw = draw,
            .handleEvent = handleEvent,
            .getMaxContentSize = getMaxContentSize,
            .getSize = getSize,
        },
    };
}

pub fn scrollDown(self: *@This()) void {
    self.offset[1] = self.child.getMaxContentSize()[1];
}

pub fn getSize(opaquePtr: *const anyopaque) Vec2f {
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    return self.base.size;
}

// Get the size exclusive the visible scrollbars.
pub fn getVisibleSize(self: *@This()) Vec2f {
    return .{
        @max(0, self.base.size[0] - @as(f32, if (self.scrollbarY.visible) SCROLLBAR_SIZE else 0)),
        @max(0, self.base.size[1] - @as(f32, if (self.scrollbarX.visible) SCROLLBAR_SIZE else 0)),
    };
}
