const std = @import("std");

const Application = @import("ui/Application.zig");
const TextInput = @import("ui/widget/TextInput.zig");
const Widget = @import("ui/widget/Widget.zig");
const ScrollContainer = @import("ui/widget/ScrollContainer.zig");

fn loadFile(allocator: std.mem.Allocator, path: []const u8, textInput: *TextInput) !void {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    var buffer = std.mem.zeroes([1024]u8);
    var reader = std.fs.File.Reader.init(file, &buffer);
    try textInput.load(allocator, &reader.interface);
}

fn saveFile(path: []const u8, textInput: *TextInput) !void {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
    defer file.close();

    var buffer = std.mem.zeroes([1024]u8);
    var writer = std.fs.File.Writer.init(file, &buffer);
    try textInput.save(&writer.interface);

    std.log.debug("File {s} saved", .{path});
}

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

    var filePath: ?[]const u8 = null;

    {
        var argsIt = try std.process.ArgIterator.initWithAllocator(allocator);
        defer argsIt.deinit();

        _ = argsIt.next(); // Skip name of executable
        if (argsIt.next()) |firstArg| {
            try loadFile(allocator, firstArg, &textInput);
            filePath = firstArg;
        }
    }

    var drawNextFrame = true;
    var frames: u32 = 0;

    while (!app.shouldClose()) {
        try app.pollEvents();
        while (app.inputQueue.pop()) |event| {
            std.log.debug("Event {any}", .{event});

            drawNextFrame = true;
            switch (event) {
                .key => |keyEvent| {
                    if (keyEvent.type == .pressed) {
                        if (keyEvent.ctrl and keyEvent.code == .num1) {
                            const newFontSize: i32 = @min(textInput.fontAtlas.fontSize + 4, 52);
                            textInput.setFontSize(&app.fontManager, newFontSize);
                            drawNextFrame = true;
                        } else if (keyEvent.ctrl and keyEvent.code == .num2) {
                            const newFontSize: i32 = @max(textInput.fontAtlas.fontSize - 4, 12);
                            textInput.setFontSize(&app.fontManager, newFontSize);
                            drawNextFrame = true;
                        } else if (keyEvent.ctrl and keyEvent.code == .num3) {
                            textInput.showGrid = !textInput.showGrid;
                            drawNextFrame = true;
                        } else if (keyEvent.ctrl and keyEvent.code == .s) {
                            if (filePath) |path| {
                                try saveFile(path, &textInput);
                            }
                            drawNextFrame = true;
                        }
                    }
                },
                else => {},
            }
            drawNextFrame |= try scrollContainerWidget.handleEvent(event);
        }
        drawNextFrame |= app.handleHover(&scrollContainerWidget);
        if (drawNextFrame) {
            frames +%= 1;
            const title = try std.fmt.allocPrint(allocator, "Frames: {}", .{frames});
            defer allocator.free(title);
            app.setWindowTitle(title);

            app.layout(&scrollContainerWidget);
            try app.draw(&scrollContainerWidget);
            drawNextFrame = false;
        }
    }
}
