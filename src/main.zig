const std = @import("std");
const rl = @import("raylib");

const Application = @import("ui/Application.zig");
const Widget = @import("ui/widget/Widget.zig");
const TextInput = @import("ui/widget/TextInput.zig");

pub fn loadFromFile(self: *@This()) void {
    _ = self;
}

pub fn writeToFile(self: *@This(), path: []const u8) void {
    _ = self;
    _ = path;
}

pub fn main() anyerror!void {
    var debugAllocator = std.heap.DebugAllocator(.{}){};
    const allocator = debugAllocator.allocator();
    defer {
        const result = debugAllocator.deinit();
        if (result == .ok) {
            std.log.debug("alloc.deinit() => ok", .{});
        } else {
            std.log.debug("alloc.deinit() => leak", .{});
        }
    }

    var app = try Application.init(.{
        .width = 800,
        .height = 600,
        .title = "Text Editor",
    }, allocator);
    defer app.deinit(allocator);

    var textInput = try TextInput.init(allocator);
    var textInputWidget = textInput.widget(&app);
    defer textInputWidget.deinit();

    const text = rl.loadFileText(@ptrCast("./build.zig"));
    try textInput.loadText(text[0..]);

    while (!app.shouldClose()) {
        app.keyboardInputMode = .Character;
        try app.draw(&textInputWidget);
        try app.pollEvents();
        while (app.inputQueue.pop()) |event| {
            std.log.debug("Event {?}", .{event});
            if (event == .keyEvent and event.keyEvent.ctrl and event.keyEvent.code == .num1) {
                textInput.fontSize += 4;
            } else if (event == .keyEvent and event.keyEvent.ctrl and event.keyEvent.code == .num2) {
                textInput.fontSize = @max(textInput.fontSize - 4, 0);
            }
            try textInputWidget.handleEvent(event);
        }
    }
}
