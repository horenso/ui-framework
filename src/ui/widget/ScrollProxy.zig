const std = @import("std");
const rl = @import("raylib");

const Application = @import("../Application.zig");
const Event = @import("../event.zig").Event;
const Font = @import("../Font.zig");
const FontManager = @import("../FontManager.zig");
const Widget = @import("./Widget.zig");
const ScrollContainer = @import("./ScrollContainer.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;

scrollContainer: ?*ScrollContainer,

pub fn goToTop(self: *@This()) void {
    if (self.scrollContainer) |sc| {
        sc.offset[0] = 0;
    }
}

pub fn goToBottom(self: *@This(), widget: *Widget, size: Vec2f) void {
    if (self.scrollContainer) |sc| {
        const contentSize = widget.getMaxContentSize();
        const maxScroll = sc.getMaxScroll(size, contentSize);
        sc.offset[1] = maxScroll[1];
    }
}
