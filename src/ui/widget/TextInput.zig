const std = @import("std");

const sdl = @import("../sdl.zig").sdl;

const Application = @import("../Application.zig");
const Color = @import("../Color.zig");
const Event = @import("../event.zig").Event;
const FontAtlas = FontManager.FontAtlas;
const FontManager = @import("../FontManager.zig");
const Widget = @import("./Widget.zig");
const ScrollContainer = @import("./ScrollContainer.zig");
const ScrollProxy = @import("./ScrollProxy.zig");

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const Vec2i = vec.Vec2i;

const INITIAL_FONT_WIDTH = 30;
const CURSOR_COLOR = Color.init(0, 0, 0, 160);

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

fontAtlas: *FontAtlas,

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

    const fontAtlas = try fontManager.getFontAtlas(
        app.allocator,
        app.sdlState.renderer,
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
    self.fontAtlas = fontManager.getFontAtlas(self.base.app.allocator, self.base.app.sdlState.renderer, fontSize) catch unreachable;
    self.cursor.width = getCursorWidth(self.fontAtlas.width);
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
    std.log.debug("onBackspace", .{});
    if (self.cursor.col > 0) {
        _ = self.currentLine.data.orderedRemove(self.cursor.col - 1);
        self.setCursorCol(self.cursor.col - 1);
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
            if (keyEvent.type != .down) {
                return false;
            }
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
            const targetRow: usize = @intFromFloat(clickEvent.pos[1] / (self.fontAtlas.height + FontManager.FONT_SPACING));
            const targetCol: usize = @intFromFloat(@round(clickEvent.pos[0] / (self.fontAtlas.width + FontManager.FONT_SPACING)));

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
        @as(f32, @floatFromInt(self.longestLine.data.items.len)) * (self.fontAtlas.width + FontManager.FONT_SPACING) + getCursorWidth(self.fontAtlas.width),
        @as(f32, @floatFromInt(self.lines.len())) * self.fontAtlas.height,
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

    while (it) |currentNode| {
        const lineData: *LineData = @fieldParentPtr("node", currentNode);
        const codepoints = lineData.data.items;

        const indexFloat: f32 = @floatFromInt(index);
        const y: f32 = indexFloat * self.fontAtlas.height;
        const x: f32 = 0;

        if (index == self.cursor.row) {
            const maxContentSize = self.getMaxContentSizeInner();

            var rect: sdl.SDL_FRect = .{
                .x = x,
                .y = y,
                .w = maxContentSize[0] + 100,
                .h = self.fontAtlas.height,
            };

            const renderer = self.base.app.sdlState.renderer;
            _ = sdl.SDL_SetRenderDrawBlendMode(@ptrCast(renderer), sdl.SDL_BLENDMODE_BLEND);
            _ = sdl.SDL_SetRenderDrawColor(@ptrCast(renderer), 200, 200, 100, 100);
            _ = sdl.SDL_RenderFillRect(@ptrCast(renderer), &rect);
        }
        var pen_x: f32 = 0;
        for (codepoints) |cp| {
            // TODO error handling
            const glyph = self.fontAtlas.getGlyph(self.base.app.allocator, cp) catch unreachable;

            const tex_size: f32 = 1024;
            const src_rect: sdl.SDL_FRect = .{
                .x = glyph.uv[0] * tex_size,
                .y = glyph.uv[1] * tex_size,
                .w = @floatFromInt(glyph.size[0]),
                .h = @floatFromInt(glyph.size[1]),
            };

            const dst_rect: sdl.SDL_FRect = .{
                .x = pen_x + @as(f32, @floatFromInt(glyph.bearing[0])),
                .y = y - @as(f32, @floatFromInt(glyph.bearing[1])) + self.fontAtlas.height,
                .w = @floatFromInt(glyph.size[0]),
                .h = @floatFromInt(glyph.size[1]),
            };

            const renderer = self.base.app.sdlState.renderer;
            _ = sdl.SDL_SetTextureColorMod(self.fontAtlas.texture, 0, 0, 0);
            _ = sdl.SDL_RenderTexture(@ptrCast(renderer), self.fontAtlas.texture, &src_rect, &dst_rect);
            _ = sdl.SDL_SetTextureColorMod(self.fontAtlas.texture, 255, 255, 255);

            pen_x += self.fontAtlas.width;
        }

        it = currentNode.next;
        index += 1;
    }
}

fn getCursorWidth(fontWidth: f32) f32 {
    const scaled: f32 = fontWidth / 8.0;
    return @max(1, @abs(scaled));
}

pub fn draw(opaquePtr: *const anyopaque) !void {
    // rl.clearBackground(rl.Color.white);

    const self: *const @This() = @ptrCast(@alignCast(opaquePtr));

    self.drawText();

    _ = sdl.SDL_SetRenderDrawColor(
        self.base.app.sdlState.renderer,
        CURSOR_COLOR.r,
        CURSOR_COLOR.g,
        CURSOR_COLOR.b,
        CURSOR_COLOR.a,
    );
    _ = sdl.SDL_RenderFillRect(self.base.app.sdlState.renderer, &.{
        .x = self.cursor.x,
        .y = self.cursor.y,
        .w = self.cursor.width,
        .h = self.fontAtlas.height,
    });
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

    self.cursor.x = (self.fontAtlas.width + FontManager.FONT_SPACING) * @as(f32, @floatFromInt(self.cursor.col));
    self.cursor.y = self.fontAtlas.height * @as(f32, @floatFromInt(self.cursor.row));

    std.log.debug("cursor{d}:{d}", .{ row, col });

    self.scrollProxy.ensureVisible(
        .{ self.cursor.x, self.cursor.y },
        .{ self.cursor.width, self.fontAtlas.height },
    );
}
