const std = @import("std");

const Application = @import("libui/Application.zig");
const Widget = @import("libui/Widget.zig");

pub fn main() anyerror!void {
    var alloc = std.heap.DebugAllocator(.{}){};
    defer _ = alloc.deinit();

    var app = Application.init(.{ .width = 800, .height = 600, .title = "Hello, world!" }, alloc.allocator());
    defer app.close();

    var text_input = Widget{
        .payload = Widget.WidgetPayload{ .text_input = .{
            .fontSize = 16,
            .text = std.ArrayList(u8).init(alloc.allocator()),
            .cursorPos = 0,
        } },
        .pos = .{ 10, 10 },
        .size = .{ 30, 30 },
    };
    // const grid = root.Widget{ .grid = .{
    //     .pos = .{ 10, 10 },
    //     .size = .{ 500, 500 },
    //     .cols = 3,
    //     .rows = 3,
    // } };

    while (!app.shouldClose()) {
        try app.draw(&text_input, alloc.allocator());
        try app.pollEvents();
        while (app.inputQueue.pop()) |event| {
            std.log.debug("Event {?}", .{event});
            try text_input.defaultAction(event);
        }
    }
}
