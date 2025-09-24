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

const Scrollbar = struct {
    const SIZE = 14.0;

    kind: enum { x, y },
    visible: bool = false,
    length: f32 = 0,
    thumbPos: f32 = 0,
    thumbLength: f32 = 0,

    dragging: bool = false,
    dragOffset: f32 = 0,

    fn isInside(self: *const @This(), size: Vec2f, pos: Vec2f) bool {
        if (!self.visible) {
            return false;
        }
        const box: Vec4f = if (self.kind == .x) .{
            0,
            size[1] - SIZE,
            size[0],
            SIZE,
        } else .{
            size[0] - SIZE,
            0,
            SIZE,
            size[1],
        };
        return vec.isVec2fInsideVec4f(box, pos);
    }

    fn isInsideThumb(self: *const @This(), size: Vec2f, pos: Vec2f) bool {
        if (!self.visible) {
            return false;
        }
        const thumbBox: Vec4f = if (self.kind == .x) .{
            self.thumbPos,
            size[1] - SIZE,
            self.thumbLength,
            SIZE,
        } else .{
            size[0] - SIZE,
            self.thumbPos,
            SIZE,
            self.thumbLength,
        };
        return vec.isVec2fInsideVec4f(thumbBox, pos);
    }

    fn getScrolledPercentage(self: *const @This()) f32 {
        return self.thumbPos / (self.length - self.thumbLength);
    }
};

const SCROLL_SPEED = 40.0;
const SCROLL_SPEED_VEC: Vec2f = @splat(SCROLL_SPEED);

const SCROLLBAR_BACKGROUND_COLOR = Color.init(200, 200, 200, 150);
const SCROLLBAR_THUMB_COLOR = Color.init(60, 60, 60, 128);
const SCROLLBAR_THUMB_HOVERING_COLOR = Color.init(60, 60, 60, 200);
const SCROLLBAR_THUMB_DRAGGING_COLOR = Color.init(60, 60, 200, 200);

outlineColor: Color,

base: Widget.Base,
child: Widget,
offset: Vec2f = .{ 0, 0 },

scrollbarX: Scrollbar = .{ .kind = .x },
scrollbarY: Scrollbar = .{ .kind = .y },

pub fn init(app: *Application, child: Widget) @This() {
    return .{
        .base = .{ .app = app },
        .child = child,
        .outlineColor = Color.random(),
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

pub fn handleHover(opaquePtr: *anyopaque, pos: Vec2f) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    if (vec.isVec2fInsideVec4f(.{
        0,
        0,
        self.base.size[0] - if (self.scrollbarY.visible) @as(f32, Scrollbar.SIZE) else 0,
        self.base.size[1] - if (self.scrollbarX.visible) @as(f32, Scrollbar.SIZE) else 0,
    }, pos)) {
        self.child.handleHover(pos);
    }
}

pub fn layout(opaquePtr: *anyopaque, size: Vec2f) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    self.base.size = size;

    const contentSize = self.child.getMaxContentSize();

    self.setAndClampOffset(contentSize, self.offset);

    self.scrollbarX.visible = contentSize[0] > self.base.size[0];
    self.scrollbarY.visible = contentSize[1] > self.base.size[1];

    self.child.layout(contentSize);

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

    renderer.outline(.{ 0, 0, self.base.size[0], self.base.size[1] }, self.outlineColor);

    {
        renderer.setClip(.{ self.base.size[0], self.base.size[1] });

        const prevOffset = renderer.offset;
        renderer.offset -= self.offset;
        defer renderer.offset = prevOffset;

        try self.child.draw(renderer);
    }

    if (self.scrollbarX.visible) {
        renderer.fillRect(.{
            0,
            self.base.size[1] - Scrollbar.SIZE,
            self.base.size[0],
            Scrollbar.SIZE,
        }, SCROLLBAR_BACKGROUND_COLOR);
        renderer.fillRect(.{
            self.scrollbarX.thumbPos,
            self.base.size[1] - Scrollbar.SIZE,
            self.scrollbarX.thumbLength,
            Scrollbar.SIZE,
        }, SCROLLBAR_THUMB_COLOR);
    }
    if (self.scrollbarY.visible) {
        renderer.fillRect(.{
            self.base.size[0] - Scrollbar.SIZE,
            0,
            Scrollbar.SIZE,
            self.base.size[1],
        }, SCROLLBAR_BACKGROUND_COLOR);
        renderer.fillRect(.{
            self.base.size[0] - Scrollbar.SIZE,
            self.scrollbarY.thumbPos,
            Scrollbar.SIZE,
            self.scrollbarY.thumbLength,
        }, SCROLLBAR_THUMB_COLOR);
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

fn setOffsetFromPercentage(self: *@This(), contentSize: Vec2f, pos: Vec2f) void {
    const maxScroll = self.getMaxScroll(self.base.size, contentSize);

    const newOffset = maxScroll * pos;
    self.setAndClampOffset(contentSize, newOffset);
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
                newOffset[0] = self.offset[0] + mouseWheelMove[0] * SCROLL_SPEED;
            }
            if (canScrollY) {
                newOffset[1] = self.offset[1] - mouseWheelMove[1] * SCROLL_SPEED;
            }
            self.setAndClampOffset(contentSize, newOffset);

            return canScrollX or canScrollY;
        },
        .mouseButton => |mouseButton| {
            if (mouseButton.type == .up) {
                if (mouseButton.button == .left) {
                    self.scrollbarX.dragging = false;
                    self.scrollbarY.dragging = false;
                    return true;
                }
                return false;
            }
            if (mouseButton.button == .left and self.scrollbarX.isInside(self.base.size, mouseButton.pos)) {
                const contentSize = self.child.getMaxContentSize();

                if (!self.scrollbarX.isInsideThumb(self.base.size, mouseButton.pos)) {
                    // Jump: center the thumb on the click
                    const clickX = mouseButton.pos[0];

                    const spaceForOtherScrollbar: f32 = if (self.scrollbarY.visible) Scrollbar.SIZE else 0;
                    const trackLength = self.base.size[0] - spaceForOtherScrollbar;

                    const maxOffset = contentSize[0] - trackLength;
                    if (maxOffset > 0) {
                        // compute target offset from click
                        const newThumbPos = std.math.clamp(
                            clickX - self.scrollbarX.thumbLength / 2,
                            0,
                            trackLength - self.scrollbarX.thumbLength,
                        );

                        const scrolled = newThumbPos / (trackLength - self.scrollbarX.thumbLength);
                        const newOffset = scrolled * maxOffset;

                        self.setAndClampOffset(contentSize, .{ newOffset, self.offset[1] });
                        self.scrollbarX.dragOffset = mouseButton.pos[0] - newThumbPos;
                    }
                } else {
                    self.scrollbarX.dragOffset = mouseButton.pos[0] - self.scrollbarX.thumbPos;
                }
                self.scrollbarX.dragging = true;
                return true;
            }
            if (mouseButton.button == .left and self.scrollbarY.isInside(self.base.size, mouseButton.pos)) {
                const contentSize = self.child.getMaxContentSize();

                if (!self.scrollbarY.isInsideThumb(self.base.size, mouseButton.pos)) {
                    const clickY = mouseButton.pos[1];

                    const spaceForOtherScrollbar: f32 = if (self.scrollbarX.visible) Scrollbar.SIZE else 0;
                    const trackLength = self.base.size[1] - spaceForOtherScrollbar;

                    const maxOffset = contentSize[1] - trackLength;
                    if (maxOffset > 0) {
                        const newThumbPos = std.math.clamp(
                            clickY - self.scrollbarY.thumbLength / 2,
                            0,
                            trackLength - self.scrollbarY.thumbLength,
                        );

                        const scrolled = newThumbPos / (trackLength - self.scrollbarY.thumbLength);
                        const newOffset = scrolled * maxOffset;

                        self.setAndClampOffset(contentSize, .{ self.offset[0], newOffset });
                        self.scrollbarX.dragOffset = mouseButton.pos[1] - newThumbPos;
                    }
                } else {
                    self.scrollbarY.dragOffset = mouseButton.pos[1] - self.scrollbarY.thumbPos;
                }
                self.scrollbarY.dragging = true;
                return true;
            }
            return false;
        },
        .mouseMotion => |mouseMotion| {
            const contentSize = self.child.getMaxContentSize();

            if (!mouseMotion.buttons.left) {
                self.scrollbarX.dragging = false;
                self.scrollbarY.dragging = false;
            }

            if (self.scrollbarX.dragging) {
                const spaceForOtherScrollbar: f32 = if (self.scrollbarY.visible) Scrollbar.SIZE else 0;
                const trackLength = self.base.size[0] - spaceForOtherScrollbar;
                const maxOffset = contentSize[0] - trackLength;
                if (maxOffset > 0) {
                    const newThumbPos = std.math.clamp(
                        mouseMotion.pos[0] - self.scrollbarX.dragOffset,
                        0,
                        trackLength - self.scrollbarX.thumbLength,
                    );
                    const scrolled = newThumbPos / (trackLength - self.scrollbarX.thumbLength);
                    const newOffset = scrolled * maxOffset;
                    self.setAndClampOffset(contentSize, .{ newOffset, self.offset[1] });
                }
                return true;
            }

            if (self.scrollbarY.dragging) {
                const spaceForOtherScrollbar: f32 = if (self.scrollbarX.visible) Scrollbar.SIZE else 0;
                const trackLength = self.base.size[1] - spaceForOtherScrollbar;
                const maxOffset = contentSize[1] - trackLength;
                if (maxOffset > 0) {
                    const newThumbPos = std.math.clamp(
                        mouseMotion.pos[1] - self.scrollbarY.dragOffset,
                        0,
                        trackLength - self.scrollbarY.thumbLength,
                    );
                    const scrolled = newThumbPos / (trackLength - self.scrollbarY.thumbLength);
                    const newOffset = scrolled * maxOffset;
                    self.setAndClampOffset(contentSize, .{ self.offset[0], newOffset });
                }
                return true;
            }
            return false;
        },
        else => {},
    }
    return false;
}

pub fn handleEvent(opaquePtr: *anyopaque, event: Event) !bool {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));

    if (self.handleOwnEvent(event)) {
        return true;
    }

    const e = if (event == .mouseButton) blk: {
        var newClickEvent = event;
        newClickEvent.mouseButton.pos += self.offset;
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
            .handleHover = handleHover,
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
