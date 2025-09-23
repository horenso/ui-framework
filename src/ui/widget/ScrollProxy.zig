const std = @import("std");

const Application = @import("../Application.zig");
const Event = @import("../event.zig").Event;
const FontManager = @import("../FontManager.zig");
const Widget = @import("./Widget.zig");
const ScrollContainer = @import("./ScrollContainer.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;

scrollContainer: ?*ScrollContainer,

// If the point is not in the scroll view, it scrolls to at least this offset
pub fn ensureVisible(self: *@This(), pos: Vec2f, size: Vec2f) void {
    if (self.scrollContainer) |sc| {
        std.debug.assert(pos[0] >= 0 and pos[1] >= 0);
        std.debug.assert(size[0] >= 0 and size[1] >= 0);

        const visibleSize = sc.getVisibleSize();

        sc.offset = .{
            std.math.clamp(sc.offset[0], pos[0] + size[0] - visibleSize[0], pos[0]),
            std.math.clamp(sc.offset[1], pos[1] + size[1] - visibleSize[1], pos[1]),
        };
    }
}

pub fn goToTop(self: *@This()) void {
    if (self.scrollContainer) |sc| {
        sc.offset[0] = 0;
    }
}

pub fn goToBottom(self: *@This(), widget: Widget, size: Vec2f) void {
    if (self.scrollContainer) |sc| {
        const contentSize = widget.getMaxContentSize();
        const maxScroll = sc.getMaxScroll(size, contentSize);
        sc.offset[1] = maxScroll[1];
    }
}
