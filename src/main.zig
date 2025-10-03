const std = @import("std");

const sdl = @import("ui/sdl.zig").sdl;

const Application = @import("ui/Application.zig");
const Event = @import("ui/event.zig").Event;
const EventHandler = @import("ui/EventHandler.zig");
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

const Context = struct {
    app: *Application,
    textInput: *TextInput,
    scrollContainer: *ScrollContainer,
    filePath: ?[]const u8,

    pub fn eventHandler(self: *@This()) EventHandler {
        return .{
            .ptr = self,
            ._handler = _handleEvent,
        };
    }

    pub fn _handleEvent(opaquePtr: *anyopaque, event: Event) !bool {
        const self: *@This() = @ptrCast(@alignCast(opaquePtr));
        switch (event) {
            .key => |keyEvent| {
                if (keyEvent.type == .pressed) {
                    if (keyEvent.ctrl and keyEvent.code == .num1) {
                        const newFontSize: i32 = @min(self.textInput.fontAtlas.fontSize + 4, 52);
                        self.textInput.setFontSize(&self.app.fontManager, newFontSize);
                        return true;
                    } else if (keyEvent.ctrl and keyEvent.code == .num2) {
                        const newFontSize: i32 = @max(self.textInput.fontAtlas.fontSize - 4, 12);
                        self.textInput.setFontSize(&self.app.fontManager, newFontSize);
                        return true;
                    } else if (keyEvent.ctrl and keyEvent.code == .num3) {
                        self.textInput.showGrid = !self.textInput.showGrid;
                        return true;
                    } else if (keyEvent.ctrl and keyEvent.code == .s) {
                        if (self.filePath) |path| {
                            try saveFile(path, self.textInput);
                            return true;
                        }
                    }
                }
            },
            else => {},
        }
        return false;
    }
};

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

    var scrollContainer = ScrollContainer.init(&app, textInputWidget, 40);
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

    var context: Context = .{
        .app = &app,
        .filePath = filePath,
        .scrollContainer = &scrollContainer,
        .textInput = &textInput,
    };

    app.eventHandler = context.eventHandler();

    try app.startEventLoop(allocator, scrollContainerWidget);
}
