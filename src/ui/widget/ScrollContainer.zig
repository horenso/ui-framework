const std = @import("std");

const sdl = @import("../sdl.zig").sdl;

const Application = @import("../Application.zig");
const Color = Renderer.Color;
const Event = @import("../event.zig").Event;
const RectF = Renderer.RectF;
const Renderer = @import("../Renderer.zig");
const Widget = @import("./Widget.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;

const Scrollbar = struct {
    const SIZE = 14.0;

    kind: enum { x, y },
    visible: bool = false,
    length: f32 = 0,
    thumbPos: f32 = 0,
    thumbLength: f32 = 0,

    fn isInside(self: *@This(), size: Vec2f, pos: Vec2f) bool {
        if (self.kind == .x) {
            return pos[0] >= size[0] - SIZE and
                pos[0] <= size[0] and
                pos[1] <= size[1];
        } else {
            return pos[1] >= size[1] - SIZE and
                pos[1] <= size[1] and
                pos[0] <= size[0];
        }
    }

    fn isInsideThumb(_: *@This(), _: Vec2f, _: Vec2f) bool {
        return false;
    }
};

const SCROLL_SPEED = 40.0;
const SCROLL_SPEED_VEC: Vec2f = @splat(SCROLL_SPEED);

const SCROLLBAR_BACKGROUND_COLOR = Color.init(200, 200, 200, 150);
const SCROLLBAR_FOREGROUND_COLOR = Color.init(60, 60, 60, 128);

base: Widget.Base,
child: Widget,
offset: Vec2f = .{ 0, 0 },

scrollbarX: Scrollbar = .{ .kind = .x },
scrollbarY: Scrollbar = .{ .kind = .y },

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
        const spaceForOtherScrollbar: f32 = if (self.scrollbarY.visible) Scrollbar.SIZE else 0;
        self.scrollbarX.length = self.base.size[0] - spaceForOtherScrollbar;

        const ratio = (self.base.size[0] - spaceForOtherScrollbar) / contentSize[0];
        self.scrollbarX.thumbLength = self.scrollbarX.length * ratio;

        const scrolled = self.offset[0] / (contentSize[0] - self.scrollbarX.length);
        self.scrollbarX.thumbPos = (self.scrollbarX.length - self.scrollbarX.thumbLength) * scrolled;
    }

    if (self.scrollbarY.visible) {
        const spaceForOtherScrollbar: f32 = if (self.scrollbarX.visible) Scrollbar.SIZE else 0;
        self.scrollbarY.length = self.base.size[1] - spaceForOtherScrollbar;

        const ratio = (self.base.size[1] - spaceForOtherScrollbar) / contentSize[1];
        self.scrollbarY.thumbLength = self.scrollbarY.length * ratio;

        const scrolled = self.offset[1] / (contentSize[1] - self.scrollbarY.length);
        self.scrollbarY.thumbPos = (self.scrollbarY.length - self.scrollbarY.thumbLength) * scrolled;
    }
}

pub fn draw(opaquePtr: *const anyopaque, renderer: *Renderer) !void {
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));

    {
        const prevOffset = renderer.offset;
        renderer.offset -= self.offset;
        defer renderer.offset = prevOffset;

        try self.child.draw(renderer);
    }

    if (self.scrollbarX.visible) {
        renderer.fillRect(.{
            .x = 0,
            .y = self.base.size[1] - Scrollbar.SIZE,
            .w = self.base.size[0],
            .h = Scrollbar.SIZE,
        }, SCROLLBAR_BACKGROUND_COLOR);
        renderer.fillRect(.{
            .x = self.scrollbarX.thumbPos,
            .y = self.base.size[1] - Scrollbar.SIZE,
            .w = self.scrollbarX.thumbLength,
            .h = Scrollbar.SIZE,
        }, SCROLLBAR_FOREGROUND_COLOR);
    }
    if (self.scrollbarY.visible) {
        renderer.fillRect(.{
            .x = self.base.size[0] - Scrollbar.SIZE,
            .y = 0,
            .w = Scrollbar.SIZE,
            .h = self.base.size[1],
        }, SCROLLBAR_BACKGROUND_COLOR);
        renderer.fillRect(.{
            .x = self.base.size[0] - Scrollbar.SIZE,
            .y = self.scrollbarY.thumbPos,
            .w = Scrollbar.SIZE,
            .h = self.scrollbarY.thumbLength,
        }, SCROLLBAR_FOREGROUND_COLOR);
    }
}

pub fn getMaxScroll(self: *@This(), size: Vec2f, contentSize: Vec2f) Vec2f {
    const upperUnbound: Vec2f = .{
        contentSize[0] - size[0] + @as(f32, if (self.scrollbarY.visible) Scrollbar.SIZE else 0),
        contentSize[1] - size[1] + @as(f32, if (self.scrollbarX.visible) Scrollbar.SIZE else 0),
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

fn handleOwnEvent(self: *@This(), event: Event) bool {
    switch (event) {
        .mouseWheel => |mouseWheelMove| {
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
        .mouseClick => |mouseClick| {
            if (mouseClick.button == .left and self.scrollbarX.isInside(self.base.size, mouseClick.pos)) {
                std.log.debug("clicked on scrollbarX", .{});
                return true;
            }
            if (mouseClick.button == .left and self.scrollbarY.isInside(self.base.size, mouseClick.pos)) {
                std.log.debug("clicked on scrollbarY", .{});
                return true;
            }
            return false;
        },
        else => return false,
    }
}

pub fn handleEvent(opaquePtr: *anyopaque, event: Event) !bool {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));

    if (self.handleOwnEvent(event)) {
        return true;
    }

    const e = if (event == .mouseClick) blk: {
        var newClickEvent = event;
        newClickEvent.mouseClick.pos += self.offset;
        break :blk newClickEvent;
    } else event;
    const childHandledEvent = try self.child.handleEvent(e);

    return childHandledEvent;
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
        @max(0, self.base.size[0] - @as(f32, if (self.scrollbarY.visible) Scrollbar.SIZE else 0)),
        @max(0, self.base.size[1] - @as(f32, if (self.scrollbarX.visible) Scrollbar.SIZE else 0)),
    };
}
