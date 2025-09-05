const std = @import("std");
const rl = @import("raylib");

const Application = @import("ui/Application.zig");
const TextInput = @import("ui/widget/TextInput.zig");
const Widget = @import("ui/widget/Widget.zig");
const ScrollContainer = @import("ui/widget/ScrollContainer.zig");

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

    var textInput = try TextInput.init(&app, &app.fontManager);
    var textInputWidget = textInput.widget();
    defer textInputWidget.deinit();

    var scrollContainer = ScrollContainer.init(&app, textInputWidget);
    var scrollContainerWidget = scrollContainer.widget();
    defer scrollContainerWidget.deinit();

    textInput.setScrollContainer(&scrollContainer);

    var argsIt = std.process.args();
    _ = argsIt.next(); // Skip name of executable
    if (argsIt.next()) |firstArg| {
        const text = rl.loadFileText(@ptrCast(firstArg));
        try textInput.loadText(allocator, text[0..]);
    }

    while (!app.shouldClose()) {
        app.layout(&scrollContainerWidget);
        try app.draw(&scrollContainerWidget);
        try app.pollEvents();
        while (app.inputQueue.pop()) |event| {
            std.log.debug("Event {any}", .{event});
            if (event == .keyEvent and event.keyEvent.ctrl and event.keyEvent.code == .num1) {
                const newFontSize: i32 = @intFromFloat(textInput.font.height + 4);
                textInput.changeFontSize(&app.fontManager, newFontSize);
            } else if (event == .keyEvent and event.keyEvent.ctrl and event.keyEvent.code == .num2) {
                const newFontSize: i32 = @intFromFloat(@max(textInput.font.height - 4, 0));
                textInput.changeFontSize(&app.fontManager, newFontSize);
            }
            _ = try scrollContainerWidget.handleEvent(event);
        }
    }
}
