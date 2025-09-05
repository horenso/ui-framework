const std = @import("std");
const rl = @import("raylib");

const Application = @import("../Application.zig");
const Event = @import("../event.zig").Event;
const Font = @import("../Font.zig");
const FontManager = @import("../FontManager.zig");
const Widget = @import("./Widget.zig");
const ScrollContainer = @import("./ScrollContainer.zig");
const ScrollProxy = @import("./ScrollProxy.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const Vec2i = vec.Vec2i;

const INITIAL_FONT_WIDTH = 30;
const CURSOR_COLOR = rl.Color.init(0, 0, 0, 160);

const DEBUG_PRINT_CHAR_OUTLINE = false;

const LineData = struct {
    node: std.DoublyLinkedList.Node,
    data: std.ArrayList(u32),
};

const Cursor = struct {
    row: usize = 0,
    col: usize = 0,
    x: f32 = 0,
    y: f32 = 0,
    width: f32,
};

base: Widget.Base,

font: Font,

lines: std.DoublyLinkedList = .{},
currentLine: *LineData,
longestLine: *LineData,

cursor: Cursor,

scrollProxy: ScrollProxy,

pub fn init(app: *Application, fontManager: *FontManager) !@This() {
    var lines: std.DoublyLinkedList = .{};
    var emptyLine: *LineData = try app.allocator.create(LineData);
    emptyLine.* = std.mem.zeroes(LineData);
    emptyLine.data = .empty;
    lines.append(&emptyLine.node);

    const font = fontManager.getFont(INITIAL_FONT_WIDTH);

    return .{
        .base = .{ .app = app },
        .font = font,
        .lines = lines,
        .currentLine = emptyLine,
        .longestLine = emptyLine,
        .cursor = .{ .width = getCursorWidth(font.width) },
        .scrollProxy = .{ .scrollContainer = null },
    };
}

pub fn setScrollContainer(self: *@This(), scrollContainer: *ScrollContainer) void {
    self.scrollProxy.scrollContainer = scrollContainer;
}

pub fn widget(self: *@This()) Widget {
    return .{
        .ptr = self,
        .vtable = &.{
            .deinit = deinit,
            .layout = layout,
            .draw = draw,
            .handleEvent = handleEvent,
            .getMaxContentSize = getMaxContentSize,
            .getSize = getSize,
        },
    };
}

inline fn deinitLines(self: *@This()) void {
    var it = self.lines.first;
    while (it) |currentNode| {
        it = currentNode.next;

        const line: *LineData = @fieldParentPtr("node", currentNode);
        self.lines.remove(currentNode);
        line.data.deinit(self.base.app.allocator);
        self.base.app.allocator.destroy(line);
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
    const newLine = try self.base.app.allocator.create(LineData);
    newLine.data = std.ArrayList(u32).empty;
    return newLine;
}

pub fn changeFontSize(self: *@This(), fontManager: *FontManager, fontSize: i32) void {
    self.font = fontManager.getFont(fontSize);
    self.cursor.width = getCursorWidth(self.font.width);
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
    if (self.cursor.col > 0) {
        self.setCursorCol(self.cursor.col - 1);
    } else if (self.currentLine.node.prev) |prevLine| {
        self.currentLine = @fieldParentPtr("node", prevLine);
        self.setCursor(self.cursor.row - 1, self.currentLine.data.items.len);
    }
}

fn onRight(self: *@This()) void {
    if (self.cursor.col < self.currentLine.data.items.len) {
        self.setCursorCol(self.cursor.col + 1);
    } else if (self.currentLine.node.next) |nextLine| {
        self.currentLine = @fieldParentPtr("node", nextLine);
        self.setCursor(self.cursor.row + 1, self.cursor.col);
    }
}

fn onUp(self: *@This()) void {
    if (self.currentLine.node.prev) |prevLine| {
        self.currentLine = @fieldParentPtr("node", prevLine);
        self.setCursor(
            self.cursor.row - 1,
            @min(self.currentLine.data.items.len, self.cursor.col),
        );
    }
}

fn onDown(self: *@This()) void {
    if (self.currentLine.node.next) |nextLine| {
        self.currentLine = @fieldParentPtr("node", nextLine);
        self.setCursor(
            self.cursor.row + 1,
            @min(self.currentLine.data.items.len, self.cursor.col),
        );
    }
}

fn onEnter(self: *@This()) !void {
    const newLine = try self.base.app.allocator.create(LineData);
    newLine.data = std.ArrayList(u32).empty;
    try newLine.data.appendSlice(self.base.app.allocator, self.currentLine.data.items[self.cursor.col..]);
    self.currentLine.data.shrinkAndFree(self.base.app.allocator, self.cursor.col);
    self.lines.insertAfter(&self.currentLine.node, &newLine.node);
    self.currentLine = newLine;
    self.setCursor(self.cursor.row + 1, 0);
}

fn onBackspace(self: *@This()) !void {
    if (self.cursor.col > 0) {
        self.cursor.col -= 1;
        _ = self.currentLine.data.orderedRemove(self.cursor.col);
    } else if (self.currentLine.node.prev) |prevLine| {
        self.lines.remove(&self.currentLine.node);

        const line: *LineData = @fieldParentPtr("node", prevLine);
        self.setCursor(self.cursor.row - 1, line.data.items.len);

        try line.data.appendSlice(self.base.app.allocator, self.currentLine.data.items[0..]);
        self.currentLine.data.deinit(self.base.app.allocator);
        self.base.app.allocator.destroy(self.currentLine);
        self.currentLine = line;

        self.findLongestLine();
    }
}

fn onDelete(self: *@This()) !void {
    if (self.cursor.col < self.currentLine.data.items.len) {
        _ = self.currentLine.data.orderedRemove(self.cursor.col);
        if (self.currentLine == self.longestLine) {
            self.findLongestLine();
        }
    } else if (self.currentLine.node.next) |nextLine| {
        const line: *LineData = @fieldParentPtr("node", nextLine);
        try self.currentLine.data.appendSlice(self.base.app.allocator, line.data.items[0..]);
        self.lines.remove(nextLine);
        line.data.deinit(self.base.app.allocator);
        self.base.app.allocator.destroy(nextLine);

        self.findLongestLine();
    }
}

pub fn deinit(opaquePtr: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    self.deinitLines();
}

pub fn handleEvent(opaquePtr: *anyopaque, event: Event) !bool {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    switch (event) {
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
        .textEvent => |textEvent| {
            try self.currentLine.data.insert(self.base.app.allocator, self.cursor.col, textEvent.char);
            if (self.currentLine.data.items.len > self.longestLine.data.items.len) {
                self.longestLine = self.currentLine;
            }
            self.setCursorCol(self.cursor.col + 1);

            return true;
        },
        .clickEvent => |clickEvent| {
            // This is the cell the user clicked on, now we need to figure out if it's within the text
            const targetRow: usize = @intFromFloat(clickEvent.pos[1] / (self.font.height + Font.SPACING));
            const targetCol: usize = @intFromFloat(@round(clickEvent.pos[0] / (self.font.width + Font.SPACING)));

            var currentNode = self.lines.first;
            var index: usize = 0;
            while (currentNode) |node| {
                if (index == targetRow) {
                    self.currentLine = @fieldParentPtr("node", node);
                    break;
                }
                currentNode = node.next;
                index += 1;
            }
            self.setCursor(
                @min(targetRow, index),
                @min(targetCol, self.currentLine.data.items.len),
            );

            std.log.debug("click {any} {any} {any}", .{ targetRow, targetCol, self.cursor });

            return true;
        },
        else => return false,
    }
}

inline fn getMaxContentSizeInner(self: *const @This()) Vec2f {
    return .{
        @as(f32, @floatFromInt(self.longestLine.data.items.len)) * (self.font.width + Font.SPACING) + getCursorWidth(self.font.width),
        @as(f32, @floatFromInt(self.lines.len())) * self.font.height,
    };
}

pub fn getMaxContentSize(opaquePtr: *const anyopaque) Vec2f {
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    return self.getMaxContentSizeInner();
}

pub fn layout(opaquePtr: *anyopaque, size: Vec2f) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    self.base.size = size;
}

fn drawText(self: *const @This()) void {
    var it = self.lines.first;
    var index: usize = 0;

    const stepX: f32 = self.font.width + Font.SPACING;

    while (it) |currentNode| {
        const lineData: *LineData = @fieldParentPtr("node", currentNode);
        const codepoints = lineData.data.items;

        const indexFloat: f32 = @floatFromInt(index);
        const y: f32 = indexFloat * self.font.height;
        var x: f32 = 0;

        if (DEBUG_PRINT_CHAR_OUTLINE) {
            for (codepoints) |_| {
                rl.drawRectangleLines(
                    @intFromFloat(x),
                    @intFromFloat(y),
                    @intFromFloat(self.font.width),
                    @intFromFloat(self.font.height),
                    rl.Color.green,
                );
                x += stepX;
            }
        }

        if (index == self.cursor.row) {
            const maxContentSize = self.getMaxContentSizeInner();
            rl.drawRectangleV(
                .{ .x = x, .y = y },
                .{ .x = maxContentSize[0] + 100, .y = self.font.height },
                rl.Color.init(200, 200, 100, 100),
            );
        }

        rl.drawTextCodepoints(
            self.font.raylibFont,
            @ptrCast(codepoints),
            .{ .x = 0, .y = y },
            self.font.height,
            Font.SPACING,
            .black,
        );

        it = currentNode.next;
        index += 1;
    }
}

fn getCursorWidth(fontWidth: f32) f32 {
    const scaled: f32 = fontWidth / 8.0;
    return @max(1, @abs(scaled));
}

pub fn draw(opaquePtr: *const anyopaque) !void {
    rl.clearBackground(rl.Color.white);

    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));

    self.drawText();

    rl.drawRectangleV(
        .{ .x = self.cursor.x, .y = self.cursor.y },
        .{ .x = self.cursor.width, .y = self.font.height },
        CURSOR_COLOR,
    );
}

pub fn getSize(opaquePtr: *const anyopaque) Vec2f {
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    return self.base.size;
}

pub fn getOffset(opaquePtr: *const anyopaque) Vec2f {
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    return self.offset;
}

pub fn setOffset(opaquePtr: *anyopaque, offset: Vec2f) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    self.offset = offset;
}

pub fn setCursorRow(self: *@This(), row: usize) void {
    self.setCursor(self, row, self.cursor.col);
}

pub fn setCursorCol(self: *@This(), col: usize) void {
    self.setCursor(self.cursor.row, col);
}

pub fn setCursor(self: *@This(), row: usize, col: usize) void {
    self.cursor.row = row;
    self.cursor.col = col;

    self.cursor.x = (self.font.width + Font.SPACING) * @as(f32, @floatFromInt(self.cursor.col));
    self.cursor.y = self.font.height * @as(f32, @floatFromInt(self.cursor.row));

    self.scrollProxy.ensureVisible(
        .{ self.cursor.x, self.cursor.y },
        .{ self.cursor.width, self.font.height },
    );
}
