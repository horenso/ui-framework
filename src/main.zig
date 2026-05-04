const std = @import("std");

const sdl = @import("sdl");

const Application = @import("ui/Application.zig");
const Event = @import("ui/event.zig").Event;
const EventHandler = @import("ui/EventHandler.zig");
const TextInput = @import("ui/widget/TextInput.zig");
const Widget = @import("ui/widget/Widget.zig");
const ScrollContainer = @import("ui/widget/ScrollContainer.zig");

fn loadFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8, textInput: *TextInput) !void {
    const file = try std.Io.Dir.openFile(.cwd(), io, path, .{ .mode = .read_only });
    defer file.close(io);

    var buffer = std.mem.zeroes([1024]u8);
    var reader = std.Io.File.Reader.init(file, io, &buffer);
    try textInput.load(allocator, &reader.interface);
}

fn saveFile(io: std.Io, path: []const u8, textInput: *TextInput) !void {
    const file = try std.Io.Dir.openFile(.cwd(), io, path, .{ .mode = .read_write });
    defer file.close(io);

    var buffer = std.mem.zeroes([1024]u8);
    var writer = std.Io.File.Writer.init(file, io, &buffer);
    try textInput.save(&writer.interface);

    std.log.debug("File {s} saved", .{path});
}

const Context = struct {
    app: *Application,
    textInput: *TextInput,
    scrollContainer: *ScrollContainer,
    filePath: ?[]const u8,
    io: std.Io,

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
                    if (keyEvent.code == .f1) {
                        const newFontSize: i32 = @min(self.textInput.fontAtlas.fontSize + 4, 52);
                        self.textInput.setFontSize(&self.app.fontManager, newFontSize);
                        return true;
                    } else if (keyEvent.code == .f2) {
                        const newFontSize: i32 = @max(self.textInput.fontAtlas.fontSize - 4, 12);
                        self.textInput.setFontSize(&self.app.fontManager, newFontSize);
                        return true;
                    } else if (keyEvent.code == .f3) {
                        self.textInput.showGrid = !self.textInput.showGrid;
                        return true;
                    } else if (keyEvent.code == .f4) {
                        self.app.debugDrawVirtualWindow = !self.app.debugDrawVirtualWindow;
                        return true;
                    } else if (keyEvent.code == .f5) {
                        self.app.debugDrawOutlines = !self.app.debugDrawOutlines;
                        return true;
                    } else if (keyEvent.ctrl and keyEvent.code == .s) {
                        if (self.filePath) |path| {
                            try saveFile(self.io, path, self.textInput);
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

pub fn main(init: std.process.Init) anyerror!void {
    const allocator = init.gpa;

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
        var argsIt = try init.minimal.args.iterateAllocator(allocator);
        defer argsIt.deinit();

        _ = argsIt.skip(); // Skip name of executable
        if (argsIt.next()) |firstArg| {
            try loadFile(allocator, init.io, firstArg, &textInput);
            filePath = firstArg;
        }
    }

    var context: Context = .{
        .app = &app,
        .filePath = filePath,
        .scrollContainer = &scrollContainer,
        .textInput = &textInput,
        .io = init.io,
    };

    app.eventHandler = context.eventHandler();

    try app.startEventLoop(allocator, scrollContainerWidget);
}
