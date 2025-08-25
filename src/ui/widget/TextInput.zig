const std = @import("std");
const rl = @import("raylib");

const Application = @import("../Application.zig");
const Event = @import("../event.zig").Event;
const Widget = @import("./Widget.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const Vec2i = vec.Vec2i;

const FONT_SPACING = 2;

pub const LinesType = std.DoublyLinkedList(std.ArrayList(u32));

fontSize: i32,
lines: LinesType,
currentLine: *LinesType.Node,
maxLineLength: usize,
cursorRow: usize,
cursorCol: usize,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !@This() {
    var lines = LinesType{};
    var emptyLine: *LinesType.Node = try allocator.create(LinesType.Node);
    emptyLine.data = std.ArrayList(u32).init(allocator);
    lines.append(emptyLine);
    return .{
        .fontSize = 30,
        .lines = lines,
        .currentLine = emptyLine,
        .maxLineLength = 0,
        .cursorRow = 0,
        .cursorCol = 0,
        .allocator = allocator,
    };
}

pub fn widget(self: *@This(), app: *Application) Widget {
    return .{
        .app = app,
        .ptr = self,
        .vtable = &.{
            .deinit = deinit,
            .draw = draw,
            .handleEvent = handleEvent,
            .getMaxContentSize = getMaxContentSize,
        },
    };
}

inline fn deinitLines(self: *@This()) void {
    var it = self.lines.first;
    while (it) |currentLine| {
        it = currentLine.next;
        self.lines.remove(currentLine);
        currentLine.data.deinit();
        self.allocator.destroy(currentLine);
    }
}

fn makeNewLine(self: *@This()) !*LinesType.Node {
    const newLine = try self.allocator.create(LinesType.Node);
    newLine.data = std.ArrayList(u32).init(self.allocator);
    return newLine;
}

pub fn loadText(self: *@This(), utf8Text: []const u8) !void {
    self.deinitLines();

    var lines_it = std.mem.splitSequence(u8, utf8Text, "\n");
    while (lines_it.next()) |line| {
        var newLine = try self.makeNewLine();
        self.lines.append(newLine);

        var viewer = try std.unicode.Utf8View.init(line);
        var it = viewer.iterator();

        while (it.nextCodepoint()) |cp| {
            try newLine.data.append(@intCast(cp));
        }
    }
    if (self.lines.first) |firstLine| {
        self.currentLine = firstLine;
    } else {
        const newLine = try self.makeNewLine();
        self.lines.append(newLine);
    }
}

fn onLeft(self: *@This()) void {
    if (self.cursorCol > 0) {
        self.cursorCol -= 1;
    } else if (self.currentLine.prev) |prevLine| {
        self.cursorRow -= 1;
        self.currentLine = prevLine;
        self.cursorCol = self.currentLine.data.items.len;
    }
}

fn onRight(self: *@This()) void {
    if (self.cursorCol < self.currentLine.data.items.len) {
        self.cursorCol += 1;
    } else if (self.currentLine.next) |nextLine| {
        self.cursorRow += 1;
        self.currentLine = nextLine;
        self.cursorCol = 0;
    }
}

fn onUp(self: *@This()) void {
    if (self.currentLine.prev) |prevLine| {
        self.cursorRow -= 1;
        self.currentLine = prevLine;
        self.cursorCol = @min(self.currentLine.data.items.len, self.cursorCol);
    }
}

fn onDown(self: *@This()) void {
    if (self.currentLine.next) |nextLine| {
        self.cursorRow += 1;
        self.currentLine = nextLine;
        self.cursorCol = @min(self.currentLine.data.items.len, self.cursorCol);
    }
}

fn onEnter(self: *@This()) !void {
    const newLine = try self.allocator.create(LinesType.Node);
    newLine.data = std.ArrayList(u32).init(self.allocator);
    try newLine.data.appendSlice(self.currentLine.data.items[self.cursorCol..]);
    self.currentLine.data.shrinkAndFree(self.cursorCol);
    self.lines.insertAfter(self.currentLine, newLine);
    self.currentLine = newLine;
    self.cursorCol = 0;
    self.cursorRow += 1;
}

fn onBackspace(self: *@This()) !void {
    if (self.cursorCol > 0) {
        self.cursorCol -= 1;
        _ = self.currentLine.data.orderedRemove(self.cursorCol);
    } else if (self.currentLine.prev) |prevLine| {
        self.lines.remove(self.currentLine);

        self.cursorCol = prevLine.data.items.len;
        self.cursorRow -= 1;

        try prevLine.data.appendSlice(self.currentLine.data.items[0..]);
        self.currentLine.data.deinit();
        self.allocator.destroy(self.currentLine);
        self.currentLine = prevLine;
    }
}

fn onDelete(self: *@This()) !void {
    if (self.cursorCol < self.currentLine.data.items.len) {
        _ = self.currentLine.data.orderedRemove(self.cursorCol);
    } else if (self.currentLine.next) |nextLine| {
        try self.currentLine.data.appendSlice(nextLine.data.items[0..]);
        self.lines.remove(nextLine);
        nextLine.data.deinit();
        self.allocator.destroy(nextLine);
    }
}

pub fn deinit(opaquePtr: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    self.deinitLines();
}

pub fn handleEvent(opaquePtr: *anyopaque, app: *Application, event: Event) !bool {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    switch (event) {
        .charEvent => |character| {
            // var buffer: [4]u8 = std.mem.zeroes([4]u8);
            // const encoded = std.unicode.utf8Encode(character, &buffer) catch unreachable;
            // try self.codepoints.insertSlice(self.cursorCol, buffer[0..encoded]);
            try self.currentLine.data.insert(self.cursorCol, character);
            self.maxLineLength = @max(self.maxLineLength, self.currentLine.data.items.len);
            self.cursorCol += 1;
            return true;
        },
        .keyEvent => |keyEvent| {
            switch (keyEvent.code) {
                .left => self.onLeft(),
                .right => self.onRight(),
                .down => self.onDown(),
                .up => self.onUp(),
                .enter => try self.onEnter(),
                .backspace => try self.onBackspace(),
                .delete => try self.onDelete(),
                else => return false,
            }
            return true;
        },
        .clickEvent => |clickEvent| {
            const font = try app.fontManager.getFont(@intCast(self.fontSize));
            const fontSizeFloat: f32 = @floatFromInt(self.fontSize);
            const fontWidth = rl.measureTextEx(font, "A", fontSizeFloat, FONT_SPACING).x;

            self.cursorRow = @as(usize, @intCast(clickEvent.y)) / @as(usize, @intCast(self.fontSize));
            self.cursorCol = @as(usize, @intCast(clickEvent.x)) / @as(usize, @intFromFloat(fontWidth + FONT_SPACING));

            var currentNode = self.lines.first;
            var index: usize = 0;
            while (currentNode) |node| {
                if (index == self.cursorRow) {
                    self.currentLine = node;
                    break;
                }
                currentNode = node.next;
                index += 1;
            }
            self.cursorCol = @min(self.cursorCol, self.currentLine.data.items.len);
            return true;
        },
        else => return false,
    }
}

pub fn getMaxContentSize(opaquePtr: *const anyopaque) Vec2f {
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    const lineCount = self.lines.len;
    const fontSizeFloat: f32 = @floatFromInt(self.fontSize);
    return Vec2f{
        @as(f32, @floatFromInt(self.maxLineLength)) * fontSizeFloat + FONT_SPACING,
        @as(f32, @floatFromInt(lineCount)) * fontSizeFloat,
    };
}

pub fn draw(opaquePtr: *const anyopaque, app: *Application, position: Vec2f, size: Vec2f, offset: Vec2f) !void {
    rl.clearBackground(rl.Color.white);

    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    _ = size;
    _ = offset;
    // text:
    const font = try app.fontManager.getFont(@intCast(self.fontSize));
    const fontSizeFloat: f32 = @floatFromInt(self.fontSize);
    const fontWidth = rl.measureTextEx(font, "A", fontSizeFloat, FONT_SPACING).x;

    var currentNode = self.lines.first;
    var index: usize = 0;
    while (currentNode) |node| {
        const indexFloat: f32 = @floatFromInt(index);
        const y: f32 = position[1] + indexFloat * fontSizeFloat;
        rl.drawTextCodepoints(
            font,
            @ptrCast(node.data.items),
            rl.Vector2{ .x = position[0], .y = y },
            fontSizeFloat,
            FONT_SPACING,
            rl.Color.red,
        );
        currentNode = node.next;
        index += 1;
    }

    // draw cursor:
    const cursorX: f32 = position[0] + (fontWidth + FONT_SPACING) * @as(f32, @floatFromInt(self.cursorCol));
    const cursorY: f32 = position[1] + fontSizeFloat * @as(f32, @floatFromInt(self.cursorRow));
    rl.drawRectangle(
        @intFromFloat(cursorX),
        @intFromFloat(cursorY),
        4.0,
        self.fontSize,
        rl.Color.init(0, 0, 0, 160),
    );
}
