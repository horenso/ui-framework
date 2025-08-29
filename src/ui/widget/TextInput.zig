const std = @import("std");
const rl = @import("raylib");

const Application = @import("../Application.zig");
const Event = @import("../event.zig").Event;
const Font = @import("../Font.zig");
const FontManager = @import("../FontManager.zig");
const Widget = @import("./Widget.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const Vec2i = vec.Vec2i;

const INITIAL_FONT_WIDTH = 30;
const CURSOR_WIDTH = 4.0;

const LineData = struct {
    node: std.DoublyLinkedList.Node,
    data: std.ArrayList(u32),
};

font: Font,

lines: std.DoublyLinkedList = .{},
currentLine: *LineData,
longestLine: *LineData,
cursorRow: usize,
cursorCol: usize,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, fontManager: *FontManager) !@This() {
    var lines: std.DoublyLinkedList = .{};
    var emptyLine: *LineData = try allocator.create(LineData);
    emptyLine.* = std.mem.zeroes(LineData);
    emptyLine.data = .empty;
    lines.append(&emptyLine.node);

    const font = fontManager.getFont(INITIAL_FONT_WIDTH);

    return .{
        .font = font,
        .lines = lines,
        .currentLine = emptyLine,
        .longestLine = emptyLine,
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
            .layout = layout,
            .draw = draw,
            .handleEvent = handleEvent,
            .getMaxContentSize = getMaxContentSize,
        },
    };
}

inline fn deinitLines(self: *@This()) void {
    var it = self.lines.first;
    while (it) |currentNode| {
        it = currentNode.next;

        const line: *LineData = @fieldParentPtr("node", currentNode);
        self.lines.remove(currentNode);
        line.data.deinit(self.allocator);
        self.allocator.destroy(line);
    }
}

fn findLongestLine(self: *@This()) void {
    var it = self.lines.first;
    var longest: usize = 0;
    while (it) |currentNode| {
        it = currentNode.next;

        const line: *LineData = @fieldParentPtr("node", currentNode);
        if (line.data.items.len > longest) {
            self.longestLine = line;
            longest = line.data.items.len;
        }
    }
}

fn makeNewLine(self: *@This()) !*LineData {
    const newLine = try self.allocator.create(LineData);
    newLine.data = std.ArrayList(u32).empty;
    return newLine;
}

pub fn changeFontSize(self: *@This(), fontManager: *FontManager, fontSize: i32) void {
    self.font = fontManager.getFont(fontSize);
}

pub fn loadText(self: *@This(), allocator: std.mem.Allocator, utf8Text: []const u8) !void {
    self.deinitLines();

    var splitIterator = std.mem.splitSequence(u8, utf8Text, "\n");
    while (splitIterator.next()) |line| {
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
        self.findLongestLine();
    } else {
        const newLine = try self.makeNewLine();
        self.lines.append(&newLine.node);
        self.currentLine = newLine;
        self.longestLine = newLine;
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

        self.findLongestLine();
    }
}

fn onDelete(self: *@This()) !void {
    if (self.cursorCol < self.currentLine.data.items.len) {
        _ = self.currentLine.data.orderedRemove(self.cursorCol);
        if (self.currentLine == self.longestLine) {
            self.findLongestLine();
        }
    } else if (self.currentLine.node.next) |nextLine| {
        const line: *LineData = @fieldParentPtr("node", nextLine);
        try self.currentLine.data.appendSlice(self.allocator, line.data.items[0..]);
        self.lines.remove(nextLine);
        line.data.deinit(self.allocator);
        self.allocator.destroy(nextLine);

        self.findLongestLine();
    }
}

pub fn deinit(opaquePtr: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    self.deinitLines();
}

pub fn handleEvent(opaquePtr: *anyopaque, app: *Application, event: Event, _: Vec2f) !bool {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    switch (event) {
        .charEvent => |character| {
            // var buffer: [4]u8 = std.mem.zeroes([4]u8);
            // const encoded = std.unicode.utf8Encode(character, &buffer) catch unreachable;
            // try self.codepoints.insertSlice(self.cursorCol, buffer[0..encoded]);
            try self.currentLine.data.insert(app.allocator, self.cursorCol, character);
            if (self.currentLine.data.items.len > self.longestLine.data.items.len) {
                self.longestLine = self.currentLine;
            }
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
            self.cursorRow = @as(usize, @intCast(clickEvent.y)) / @as(usize, @intFromFloat(self.font.width));
            self.cursorCol = @as(usize, @intCast(clickEvent.x)) / @as(usize, @intFromFloat(self.font.width + Font.SPACING));

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
    return .{
        @as(f32, @floatFromInt(self.longestLine.data.items.len)) * (self.font.width + Font.SPACING) + CURSOR_WIDTH,
        @as(f32, @floatFromInt(self.lines.len())) * self.font.height,
    };
}

pub fn layout(_: *const anyopaque, _: Vec2f) void {
    // Ideas for this
    // - important for line break if on
}

pub fn draw(opaquePtr: *const anyopaque, _: *Application, position: Vec2f, size: Vec2f, offset: Vec2f) !void {
    rl.clearBackground(rl.Color.white);

    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    _ = size;
    _ = offset;

    var it = self.lines.first;
    var index: usize = 0;
    while (it) |currentNode| {
        const lineData: *LineData = @fieldParentPtr("node", currentNode);
        const indexFloat: f32 = @floatFromInt(index);
        const y: f32 = position[1] + indexFloat * self.font.height;
        rl.drawTextCodepoints(
            self.font.raylibFont,
            @ptrCast(lineData.data.items),
            rl.Vector2{ .x = position[0], .y = y },
            self.font.height,
            Font.SPACING,
            rl.Color.red,
        );
        it = currentNode.next;
        index += 1;
    }

    // draw cursor:
    const cursorX: f32 = position[0] + (self.font.width + Font.SPACING) * @as(f32, @floatFromInt(self.cursorCol));
    const cursorY: f32 = position[1] + self.font.height * @as(f32, @floatFromInt(self.cursorRow));
    rl.drawRectangleV(
        .{ .x = cursorX, .y = cursorY },
        .{ .x = CURSOR_WIDTH, .y = self.font.height },
        rl.Color.init(0, 0, 0, 160),
    );
}
