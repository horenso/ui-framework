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

const LineData = struct {
    node: std.DoublyLinkedList.Node,
    data: std.ArrayList(u32),
};

fontSize: i32,
lines: std.DoublyLinkedList = .{},
currentLine: *LineData,
maxLineLength: usize,
cursorRow: usize,
cursorCol: usize,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !@This() {
    var lines: std.DoublyLinkedList = .{};
    var emptyLine: *LineData = try allocator.create(LineData);
    emptyLine.data = .empty;
    lines.append(&emptyLine.node);
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
    while (it) |currentNode| {
        const line: *LineData = @fieldParentPtr("node", currentNode);
        it = currentNode.next;
        self.lines.remove(currentNode);
        line.data.deinit(self.allocator);
        self.allocator.destroy(line);
    }
}

fn makeNewLine(self: *@This()) !*LineData {
    const newLine = try self.allocator.create(LineData);
    newLine.data = std.ArrayList(u32).empty;
    return newLine;
}

pub fn loadText(self: *@This(), allocator: std.mem.Allocator, utf8Text: []const u8) !void {
    self.deinitLines();

    var lines_it = std.mem.splitSequence(u8, utf8Text, "\n");
    while (lines_it.next()) |line| {
        var newLine = try self.makeNewLine();
        self.lines.append(&newLine.node);

        var viewer = try std.unicode.Utf8View.init(line);
        var it = viewer.iterator();

        while (it.nextCodepoint()) |cp| {
            try newLine.data.append(allocator, @intCast(cp));
        }
    }
    if (self.lines.first) |firstLine| {
        self.currentLine = @fieldParentPtr("node", firstLine);
    } else {
        const newLine = try self.makeNewLine();
        self.lines.append(&newLine.node);
    }
}

fn onLeft(self: *@This()) void {
    if (self.cursorCol > 0) {
        self.cursorCol -= 1;
    } else if (self.currentLine.node.prev) |prevLine| {
        self.cursorRow -= 1;
        self.currentLine = @fieldParentPtr("node", prevLine);
        self.cursorCol = self.currentLine.data.items.len;
    }
}

fn onRight(self: *@This()) void {
    if (self.cursorCol < self.currentLine.data.items.len) {
        self.cursorCol += 1;
    } else if (self.currentLine.node.next) |nextLine| {
        self.cursorRow += 1;
        self.currentLine = @fieldParentPtr("node", nextLine);
        self.cursorCol = 0;
    }
}

fn onUp(self: *@This()) void {
    if (self.currentLine.node.prev) |prevLine| {
        self.cursorRow -= 1;
        self.currentLine = @fieldParentPtr("node", prevLine);
        self.cursorCol = @min(self.currentLine.data.items.len, self.cursorCol);
    }
}

fn onDown(self: *@This()) void {
    if (self.currentLine.node.next) |nextLine| {
        self.cursorRow += 1;
        self.currentLine = @fieldParentPtr("node", nextLine);
        self.cursorCol = @min(self.currentLine.data.items.len, self.cursorCol);
    }
}

fn onEnter(self: *@This()) !void {
    const newLine = try self.allocator.create(LineData);
    newLine.data = std.ArrayList(u32).empty;
    try newLine.data.appendSlice(self.allocator, self.currentLine.data.items[self.cursorCol..]);
    self.currentLine.data.shrinkAndFree(self.allocator, self.cursorCol);
    self.lines.insertAfter(&self.currentLine.node, &newLine.node);
    self.currentLine = newLine;
    self.cursorCol = 0;
    self.cursorRow += 1;
}

fn onBackspace(self: *@This()) !void {
    if (self.cursorCol > 0) {
        self.cursorCol -= 1;
        _ = self.currentLine.data.orderedRemove(self.cursorCol);
    } else if (self.currentLine.node.prev) |prevLine| {
        self.lines.remove(&self.currentLine.node);

        const line: *LineData = @fieldParentPtr("node", prevLine);
        self.cursorCol = line.data.items.len;
        self.cursorRow -= 1;

        try line.data.appendSlice(self.allocator, self.currentLine.data.items[0..]);
        self.currentLine.data.deinit(self.allocator);
        self.allocator.destroy(self.currentLine);
        self.currentLine = line;
    }
}

fn onDelete(self: *@This()) !void {
    if (self.cursorCol < self.currentLine.data.items.len) {
        _ = self.currentLine.data.orderedRemove(self.cursorCol);
    } else if (self.currentLine.node.next) |nextLine| {
        const line: *LineData = @fieldParentPtr("node", nextLine);
        try self.currentLine.data.appendSlice(self.allocator, line.data.items[0..]);
        self.lines.remove(nextLine);
        line.data.deinit(self.allocator);
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
            try self.currentLine.data.insert(app.allocator, self.cursorCol, character);
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
                    self.currentLine = @fieldParentPtr("node", node);
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
    const lineCount = self.lines.len();
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

    var it = self.lines.first;
    var index: usize = 0;
    while (it) |currentNode| {
        const lineData: *LineData = @fieldParentPtr("node", currentNode);
        const indexFloat: f32 = @floatFromInt(index);
        const y: f32 = position[1] + indexFloat * fontSizeFloat;
        rl.drawTextCodepoints(
            font,
            @ptrCast(lineData.data.items),
            rl.Vector2{ .x = position[0], .y = y },
            fontSizeFloat,
            FONT_SPACING,
            rl.Color.red,
        );
        it = currentNode.next;
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
