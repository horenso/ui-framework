const std = @import("std");
const sdl = @import("../sdl.zig").sdl;

const Application = @import("../Application.zig");
const Color = @import("../Color.zig");
const Event = @import("../event.zig").Event;
const FontAtlas = FontManager.FontAtlas;
const FontManager = @import("../FontManager.zig");
const Widget = @import("./Widget.zig");
const Renderer = @import("../Renderer.zig");
const ScrollContainer = @import("./ScrollContainer.zig");
const ScrollProxy = @import("./ScrollProxy.zig");
const Utf8Reader = @import("../Utf8Reader.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const Vec2i = vec.Vec2i;

const INITIAL_FONT_WIDTH = 20;
const CURSOR_COLOR = Color.init(0, 0, 0, 160);
const TEXT_COLOR = Color.init(0, 0, 0, 255);
const GRID_LINES_COLOR = Color.init(150, 150, 150, 255);

const LineData = struct {
    node: std.DoublyLinkedList.Node,
    data: std.ArrayList(u32),

    inline fn getFromNode(node: *std.DoublyLinkedList.Node) *@This() {
        return @fieldParentPtr("node", node);
    }
};

const Cursor = struct {
    row: usize = 0,
    col: usize = 0,
    /// Remember the col we were at when going up or down
    preferredCol: usize = 0,
    x: f32 = 0,
    y: f32 = 0,
    width: f32,
};

base: Widget.Base,

fontAtlas: *FontAtlas,

lines: std.DoublyLinkedList = .{},
currentLine: *LineData,
longestLine: *LineData,

cursor: Cursor,

scrollProxy: ScrollProxy,

showGrid: bool = false,

pub fn init(app: *Application, renderer: Renderer, fontManager: *FontManager) !@This() {
    var lines: std.DoublyLinkedList = .{};
    var emptyLine = try app.allocator.create(LineData);
    emptyLine.* = std.mem.zeroes(LineData);
    emptyLine.data = .empty;
    lines.append(&emptyLine.node);

    const fontAtlas = try fontManager.getFontAtlas(
        app.allocator,
        renderer,
        INITIAL_FONT_WIDTH,
    );

    return .{
        .base = .{ .app = app },
        .fontAtlas = fontAtlas,
        .lines = lines,
        .currentLine = emptyLine,
        .longestLine = emptyLine,
        .cursor = .{ .width = getCursorWidth(fontAtlas.width) },
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

        const line = LineData.getFromNode(currentNode);
        self.lines.remove(currentNode);
        line.data.deinit(self.base.app.allocator);
        self.base.app.allocator.destroy(line);
    }
}

fn findLongestLine(self: *@This()) void {
    self.longestLine = LineData.getFromNode(self.lines.first.?);
    var it = self.lines.first;
    var longest: usize = 0;
    while (it) |currentNode| {
        it = currentNode.next;

        const line = LineData.getFromNode(currentNode);
        if (line.data.items.len > longest) {
            self.longestLine = line;
            longest = line.data.items.len;
        }
    }
}

fn createNewLine(self: *@This()) !*LineData {
    const newLine = try self.base.app.allocator.create(LineData);
    newLine.data = std.ArrayList(u32).empty;
    return newLine;
}

pub fn setFontSize(self: *@This(), fontManager: *FontManager, fontSize: i32) void {
    self.fontAtlas = fontManager.getFontAtlas(self.base.app.allocator, self.base.app.renderer, fontSize) catch @panic("unexpected");
    self.cursor.width = getCursorWidth(self.fontAtlas.width);
    std.log.debug("new font size {d}", .{fontSize});
    self.calculateCursorPos();
}

pub fn load(self: *@This(), allocator: std.mem.Allocator, reader: *std.Io.Reader) !void {
    self.deinitLines();

    var utf8Reader = Utf8Reader.init(reader);

    var currentLine = try self.createNewLine();
    self.lines.append(&currentLine.node);

    while (try utf8Reader.nextCodepoint()) |codepoint| {
        if (codepoint == '\n') {
            currentLine = try self.createNewLine();
            self.lines.append(&currentLine.node);
        } else {
            try currentLine.data.append(allocator, @intCast(codepoint));
        }
    }
    if (self.lines.first) |firstLine| {
        self.currentLine = LineData.getFromNode(firstLine);
        self.findLongestLine();
    } else {
        const newLine = try self.createNewLine();
        self.lines.append(&newLine.node);
        self.currentLine = newLine;
        self.longestLine = newLine;
    }
}

pub fn save(self: *@This(), writer: *std.Io.Writer) !void {
    var it = self.lines.first;
    while (it) |line| {
        for (LineData.getFromNode(line).data.items) |codepoint| {
            var buffer: [4]u8 = .{ 0, 0, 0, 0 };
            const encodedLength = try std.unicode.utf8Encode(@intCast(codepoint), &buffer);
            _ = try writer.write(buffer[0..encodedLength]);
        }
        if (line.next != null) {
            _ = try writer.write("\n");
        }
        it = line.next;
    }
    try writer.flush();
}

fn goOneLeft(self: *@This()) void {
    if (self.cursor.col > 0) {
        self.setCursorCol(self.cursor.col - 1, true);
    } else if (self.currentLine.node.prev) |prevLine| {
        self.currentLine = LineData.getFromNode(prevLine);
        self.setCursor(self.cursor.row - 1, self.currentLine.data.items.len, true);
    }
}

fn goOneRight(self: *@This()) void {
    if (self.cursor.col < self.currentLine.data.items.len) {
        self.setCursorCol(self.cursor.col + 1, true);
    } else if (self.currentLine.node.next) |nextLine| {
        self.currentLine = LineData.getFromNode(nextLine);
        self.setCursor(self.cursor.row + 1, 0, true);
    }
}

fn goOneUp(self: *@This()) void {
    if (self.currentLine.node.prev) |prevLine| {
        self.currentLine = LineData.getFromNode(prevLine);
        self.setCursor(
            self.cursor.row - 1,
            @min(self.currentLine.data.items.len, self.cursor.preferredCol),
            false,
        );
    }
}

fn goOneDown(self: *@This()) void {
    if (self.currentLine.node.next) |nextLine| {
        self.currentLine = LineData.getFromNode(nextLine);
        self.setCursor(
            self.cursor.row + 1,
            @min(self.currentLine.data.items.len, self.cursor.preferredCol),
            false,
        );
    }
}

fn goToBeginningOfLine(self: *@This()) void {
    self.setCursorCol(0, true);
}

fn goToEndOfLine(self: *@This()) void {
    self.setCursorCol(self.currentLine.data.items.len, true);
}

fn goToFirstLine(self: *@This()) void {
    self.setCursor(0, 0, true);
    self.currentLine = LineData.getFromNode(self.lines.first.?);
}

fn goToLastLine(self: *@This()) void {
    self.currentLine = LineData.getFromNode(self.lines.last.?);
    const index = self.lines.len() - 1;
    self.setCursor(index, 0, true);
}

fn splitLine(self: *@This()) !void {
    const newLine = try self.createNewLine();
    try newLine.data.appendSlice(self.base.app.allocator, self.currentLine.data.items[self.cursor.col..]);
    self.currentLine.data.shrinkAndFree(self.base.app.allocator, self.cursor.col);
    self.lines.insertAfter(&self.currentLine.node, &newLine.node);
    self.currentLine = newLine;
    self.setCursor(self.cursor.row + 1, 0, true);
}

fn insertNewlineBelow(self: *@This()) !void {
    const newLine = try self.createNewLine();
    self.lines.insertAfter(&self.currentLine.node, &newLine.node);
    self.currentLine = newLine;
    self.setCursor(self.cursor.row + 1, 0, true);
}

fn deleteOneBackward(self: *@This()) !void {
    if (self.cursor.col > 0) {
        _ = self.currentLine.data.orderedRemove(self.cursor.col - 1);
        self.setCursorCol(self.cursor.col - 1, true);
    } else if (self.currentLine.node.prev) |prevLine| {
        self.lines.remove(&self.currentLine.node);

        const line = LineData.getFromNode(prevLine);
        self.setCursor(self.cursor.row - 1, line.data.items.len, true);

        try line.data.appendSlice(self.base.app.allocator, self.currentLine.data.items[0..]);
        self.currentLine.data.deinit(self.base.app.allocator);
        self.base.app.allocator.destroy(self.currentLine);
        self.currentLine = line;

        self.findLongestLine();
    }
}

fn deleteOneForward(self: *@This()) !void {
    if (self.cursor.col < self.currentLine.data.items.len) {
        _ = self.currentLine.data.orderedRemove(self.cursor.col);
        if (self.currentLine == self.longestLine) {
            self.findLongestLine();
        }
    } else if (self.currentLine.node.next) |nextLine| {
        const line = LineData.getFromNode(nextLine);
        try self.currentLine.data.appendSlice(self.base.app.allocator, line.data.items[0..]);
        self.lines.remove(nextLine);
        line.data.deinit(self.base.app.allocator);
        self.base.app.allocator.destroy(nextLine);

        self.findLongestLine();
    }
}

fn deleteCurrentLine(self: *@This()) !void {
    const prev = self.currentLine.node.prev;
    const next = self.currentLine.node.next;

    self.lines.remove(&self.currentLine.node);
    self.base.app.allocator.destroy(self.currentLine);

    if (next) |nextLine| {
        self.currentLine = LineData.getFromNode(nextLine);
        self.setCursorCol(0, true);
        self.findLongestLine();
    } else if (prev) |prevLine| {
        self.currentLine = LineData.getFromNode(prevLine);
        self.setCursor(self.cursor.row - 1, 0, true);
        self.findLongestLine();
    } else {
        const newLine = try self.createNewLine();
        self.lines.append(&newLine.node);
        self.currentLine = newLine;
        self.longestLine = newLine;
    }
}

fn goToNextWord(self: *@This()) void {
    var row = self.cursor.row;
    var col = self.cursor.col;

    while (true) {
        if (col + 1 < self.currentLine.data.items.len) {
            col += 1;
        } else if (self.currentLine.node.next) |next| {
            row += 1;
            col = 0;
            self.currentLine = LineData.getFromNode(next);
            break;
        } else {
            break;
        }
        if (self.currentLine.data.items[col] == ' ') {
            break;
        }
    }
    self.setCursor(row, col, true);
}

fn goToPreviousWord(self: *@This()) void {
    // TODO: implement go to previous word
    self.goOneLeft();
}

pub fn deinit(opaquePtr: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    self.deinitLines();
}

pub fn handleEvent(opaquePtr: *anyopaque, event: Event) !bool {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    switch (event) {
        .key => |keyEvent| {
            if (keyEvent.type != .down) {
                return false;
            }
            switch (keyEvent.code) {
                .left => {
                    if (keyEvent.ctrl) {
                        self.goToPreviousWord();
                    } else {
                        self.goOneLeft();
                    }
                },
                .right => {
                    if (keyEvent.ctrl) {
                        self.goToNextWord();
                    } else {
                        self.goOneRight();
                    }
                },
                .down => self.goOneDown(),
                .up => self.goOneUp(),
                .enter => {
                    if (keyEvent.ctrl) {
                        try self.insertNewlineBelow();
                    } else {
                        try self.splitLine();
                    }
                },
                .backspace => try self.deleteOneBackward(),
                .delete => try self.deleteOneForward(),
                .home => {
                    if (keyEvent.ctrl) {
                        self.goToFirstLine();
                    } else {
                        self.goToBeginningOfLine();
                    }
                },
                .end => {
                    if (keyEvent.ctrl) {
                        self.goToLastLine();
                    } else {
                        self.goToEndOfLine();
                    }
                },
                .d => {
                    if (keyEvent.ctrl) {
                        try self.deleteCurrentLine();
                    }
                },
                else => return false,
            }
            return true;
        },
        .text => |textEvent| {
            try self.currentLine.data.insert(self.base.app.allocator, self.cursor.col, textEvent.char);
            if (self.currentLine.data.items.len > self.longestLine.data.items.len) {
                self.longestLine = self.currentLine;
            }
            self.setCursorCol(self.cursor.col + 1, true);

            return true;
        },
        .mouseClick => |clickEvent| {
            // This is the cell the user clicked on, now we need to figure out if it's within the text
            const targetRow: usize = @intFromFloat(clickEvent.pos[1] / self.fontAtlas.height);
            const targetCol: usize = @intFromFloat(@round(clickEvent.pos[0] / self.fontAtlas.width));

            var currentNode = self.lines.first;
            var index: usize = 0;
            while (currentNode) |node| {
                if (index == targetRow) {
                    self.currentLine = LineData.getFromNode(node);
                    break;
                }
                currentNode = node.next;
                if (node.next != null) {
                    index += 1;
                }
            }
            self.setCursor(
                @min(targetRow, index),
                @min(targetCol, self.currentLine.data.items.len),
                true,
            );
            return true;
        },
        .mouseMotion => |mouseMotionEvent| {
            if (vec.isVec2fInsideVec4f(.{ 0, 0, self.base.size[0], self.base.size[1] }, mouseMotionEvent.pos)) {
                self.base.app.setPointer(.text);
            }
            return true;
        },
        else => return false,
    }
}

inline fn getMaxContentSizeInner(self: *const @This()) Vec2f {
    const r = .{
        @as(f32, @floatFromInt(self.longestLine.data.items.len)) * self.fontAtlas.width + getCursorWidth(self.fontAtlas.width),
        @as(f32, @floatFromInt(self.lines.len())) * self.fontAtlas.height,
    };
    return r;
}

pub fn getMaxContentSize(opaquePtr: *const anyopaque) Vec2f {
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));
    return self.getMaxContentSizeInner();
}

pub fn layout(opaquePtr: *anyopaque, size: Vec2f) void {
    const self: *@This() = @ptrCast(@alignCast(opaquePtr));
    self.base.size = size;
}

fn getCursorWidth(fontWidth: f32) f32 {
    const scaled: f32 = fontWidth / 8.0;
    return @max(1, @abs(scaled));
}

fn drawText(self: *const @This(), renderer: *Renderer) void {
    var it = self.lines.first;
    var index: usize = 0;

    while (it) |currentNode| {
        const lineData = LineData.getFromNode(currentNode);
        const codepoints = lineData.data.items;

        const indexFloat: f32 = @floatFromInt(index);
        const y: f32 = indexFloat * self.fontAtlas.height;
        const x: f32 = 0;

        if (index == self.cursor.row) {
            const maxContentSize = self.getMaxContentSizeInner();

            const rect: Vec4f = .{
                x,
                y,
                maxContentSize[0],
                self.fontAtlas.height,
            };
            renderer.fillRect(rect, Color.init(200, 200, 100, 100));
        }

        var penX: f32 = 0;
        for (codepoints) |codepoint| {
            renderer.drawCharacter(
                self.base.app.allocator,
                codepoint,
                self.fontAtlas,
                .{ penX, y },
                TEXT_COLOR,
            );
            penX += self.fontAtlas.width;
        }

        it = currentNode.next;
        index += 1;
    }
}

fn drawGridLines(self: *const @This(), renderer: *const Renderer) void {
    const cellHeight = self.fontAtlas.height;
    const cellWidth = self.fontAtlas.width;

    const contentSize = self.getMaxContentSizeInner();

    var lineCount: usize = 0;
    var it = self.lines.first;
    while (it) |currentNode| {
        lineCount += 1;
        it = currentNode.next;
    }

    // Draw horizontal lines for each line of text
    for (0..lineCount) |index| {
        const indexFloat: f32 = @floatFromInt(index);
        const y: f32 = (indexFloat + 1) * cellHeight;
        renderer.line(
            .{ 0, y },
            .{ contentSize[0], y },
            GRID_LINES_COLOR,
        );
        renderer.line(
            .{ 0, y + self.fontAtlas.baseline },
            .{ contentSize[0], y + self.fontAtlas.baseline },
            GRID_LINES_COLOR,
        );
    }

    // Draw vertical lines for each character cell
    for (0..self.longestLine.data.items.len) |index| {
        const indexFloat: f32 = @floatFromInt(index);
        const x: f32 = (indexFloat + 1) * cellWidth;
        renderer.line(
            .{ x, 0 },
            .{ x, contentSize[1] },
            GRID_LINES_COLOR,
        );
    }
}

pub fn draw(opaquePtr: *const anyopaque, renderer: *Renderer) !void {
    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));

    renderer.outline(.{ 0, 0, self.base.size[0], self.base.size[1] }, Color.init(255, 0, 0, 255));

    self.drawText(renderer);
    if (self.showGrid) {
        self.drawGridLines(renderer);
    }

    self.base.app.renderer.fillRect(.{
        self.cursor.x,
        self.cursor.y,
        self.cursor.width,
        self.fontAtlas.height,
    }, CURSOR_COLOR);
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

fn setCursorRow(self: *@This(), row: usize) void {
    self.setCursor(self, row, self.cursor.col, false);
}

fn setCursorCol(self: *@This(), col: usize, overridePreferredCol: bool) void {
    self.setCursor(self.cursor.row, col, overridePreferredCol);
}

fn setCursor(self: *@This(), row: usize, col: usize, overridePreferredCol: bool) void {
    self.cursor.row = row;
    self.cursor.col = col;

    if (overridePreferredCol) {
        self.cursor.preferredCol = col;
    }

    self.calculateCursorPos();

    self.scrollProxy.ensureVisible(
        .{ self.cursor.x, self.cursor.y },
        .{ self.cursor.width, self.fontAtlas.height },
    );
}

fn calculateCursorPos(self: *@This()) void {
    self.cursor.x = self.fontAtlas.width * @as(f32, @floatFromInt(self.cursor.col));
    self.cursor.y = self.fontAtlas.height * @as(f32, @floatFromInt(self.cursor.row));
}
