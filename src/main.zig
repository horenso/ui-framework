const std = @import("std");

const Application = @import("ui/Application.zig");
const TextInput = @import("ui/widget/TextInput.zig");
const Widget = @import("ui/widget/Widget.zig");
const ScrollContainer = @import("ui/widget/ScrollContainer.zig");

pub fn main() anyerror!void {
    var debugAllocator = std.heap.DebugAllocator(.{
        .verbose_log = false,
    }){};
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

    var textInput = try TextInput.init(&app, app.renderer, &app.fontManager);
    var textInputWidget = textInput.widget();
    defer textInputWidget.deinit();

    var scrollContainer = ScrollContainer.init(&app, textInputWidget);
    var scrollContainerWidget = scrollContainer.widget();
    defer scrollContainerWidget.deinit();

    textInput.setScrollContainer(&scrollContainer);

    var argsIt = std.process.args();
    _ = argsIt.next(); // Skip name of executable
    if (argsIt.next()) |firstArg| {
        const textFile = try std.fs.cwd().openFile(firstArg, .{ .mode = .read_only });

        const buffer = try allocator.alloc(u8, @intCast(try textFile.getEndPos()));
        defer allocator.free(buffer);

        _ = try textFile.readAll(buffer);
        try textInput.loadText(allocator, buffer);
    }

    while (!app.shouldClose()) {
        app.layout(&scrollContainerWidget);
        try app.draw(&scrollContainerWidget);
        try app.pollEvents();
        while (app.inputQueue.pop()) |event| {
            std.log.debug("Event {any}", .{event});
            switch (event) {
                .keyEvent => |keyEvent| {
                    if (keyEvent.type == .pressed) {
                        if (keyEvent.ctrl and keyEvent.code == .num1) {
                            const newFontSize: i32 = @intFromFloat(textInput.fontAtlas.height + 4);
                            textInput.changeFontSize(&app.fontManager, newFontSize);
                        } else if (keyEvent.ctrl and keyEvent.code == .num2) {
                            const newFontSize: i32 = @intFromFloat(@max(textInput.fontAtlas.height - 4, 0));
                            textInput.changeFontSize(&app.fontManager, newFontSize);
                        } else if (keyEvent.ctrl and keyEvent.code == .num3) {
                            textInput.showGrid = !textInput.showGrid;
                        }
                    }
                },
                else => {},
            }
            _ = try scrollContainerWidget.handleEvent(event);
        }
    }
}
