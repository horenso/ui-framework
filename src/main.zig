const std = @import("std");
const rl = @import("raylib");

const Application = @import("ui/Application.zig");
const TextInput = @import("ui/widget/TextInput.zig");
const Widget = @import("ui/widget/Widget.zig");
const Scrollable = @import("ui/widget/Scrollable.zig");

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

    var textInput = try TextInput.init(allocator, &app.fontManager);
    var textInputWidget = textInput.widget(&app);
    defer textInputWidget.deinit();

    var scrollable = Scrollable.init(textInputWidget);
    var scrollableWidget = scrollable.widget(&app);
    defer scrollableWidget.deinit();

    const text = rl.loadFileText(@ptrCast("./build.zig"));
    try textInput.loadText(allocator, text[0..]);

    while (!app.shouldClose()) {
        app.keyboardInputMode = .Character;
        Application.layout(&scrollableWidget);
        try app.draw(&scrollableWidget);
        try app.pollEvents();
        while (app.inputQueue.pop()) |event| {
            std.log.debug("Event {any}", .{event});
            if (event == .keyEvent and event.keyEvent.ctrl and event.keyEvent.code == .num1) {
                const newFontSize: i32 = @intFromFloat(textInput.font.width + 4);
                textInput.changeFontSize(&app.fontManager, newFontSize);
            } else if (event == .keyEvent and event.keyEvent.ctrl and event.keyEvent.code == .num2) {
                const newFontSize: i32 = @intFromFloat(@max(textInput.font.height - 4, 0));
                textInput.changeFontSize(&app.fontManager, newFontSize);
            }
            _ = try scrollableWidget.handleEvent(event);
        }
    }
}
