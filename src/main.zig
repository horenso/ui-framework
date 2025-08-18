const std = @import("std");
const rl = @import("raylib");

const Application = @import("ui/Application.zig");
const Widget = @import("ui/widget/Widget.zig");

pub fn loadFromFile(self: *@This()) void {
    _ = self;
}

pub fn writeToFile(self: *@This(), path: []const u8) void {
    _ = self;
    _ = path;
}

pub fn main() anyerror!void {
    var alloc = std.heap.DebugAllocator(.{}){};
    defer {
        const result = alloc.deinit();
        if (result == .ok) {
            std.log.debug("alloc.deinit() => ok", .{});
        } else {
            std.log.debug("alloc.deinit() => leak", .{});
        }
    }

    var app = try Application.init(.{
        .width = 800,
        .height = 600,
        .title = "Hello, world!",
    }, alloc.allocator());
    defer app.deinit();

    var text_input = try Widget.TextInput(alloc.allocator(), &app);
    defer text_input.deinit();
    const text = rl.loadFileText(@ptrCast("/home/jannisadamek/playground/ui-framework/build.zig"));
    try text_input.payload.text_input.loadText(text[0..]);

    while (!app.shouldClose()) {
        app.keyboardInputMode = .Character;
        try app.draw(&text_input, alloc.allocator());
        try app.pollEvents();
        while (app.inputQueue.pop()) |event| {
            std.log.debug("Event {?}", .{event});
            if (event == .keyEvent and event.keyEvent.code == .num1) {
                app.fontSize += 4;
            } else if (event == .keyEvent and event.keyEvent.code == .num2) {
                app.fontSize = @max(app.fontSize - 4, 0);
            }
            try text_input.defaultAction(event);
        }
    }
}
