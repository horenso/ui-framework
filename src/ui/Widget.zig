const std = @import("std");
const rl = @import("raylib");

const Application = @import("Application.zig");
const Event = @import("event.zig").Event;

const Vec2 = @Vector(2, f32);
const Vec4 = @Vector(4, f32);

const LinesType = std.DoublyLinkedList(std.ArrayList(u32));

const drawDebug = true;

const TextInputPayload = struct {
    lines: LinesType, // TODO! lines.len is not correct!
    lineCount: usize,
    fontSize: i32,
    currentLine: *LinesType.Node,
    cursorRow: usize,
    cursorCol: usize,
    allocator: std.mem.Allocator, // TODO: do I need it?

    pub fn loadFromFile(self: *TextInputPayload) void {
        _ = self;
    }

    pub fn writeToFile(self: *TextInputPayload, path: []const u8) void {
        _ = self;
        _ = path;
    }

    pub fn onLeft(self: *TextInputPayload) void {
        if (self.cursorCol > 0) {
            self.cursorCol -= 1;
        } else if (self.currentLine.prev) |prevLine| {
            self.cursorRow -= 1;
            self.currentLine = prevLine;
            self.cursorCol = self.currentLine.data.items.len;
        }
    }

    pub fn onRight(self: *TextInputPayload) void {
        if (self.cursorCol < self.currentLine.data.items.len) {
            self.cursorCol += 1;
        } else if (self.currentLine.next) |nextLine| {
            self.cursorRow += 1;
            self.currentLine = nextLine;
            self.cursorCol = 0;
        }
    }

    pub fn onUp(self: *TextInputPayload) void {
        if (self.currentLine.prev) |prevLine| {
            self.cursorRow -= 1;
            self.currentLine = prevLine;
            self.cursorCol = @min(self.currentLine.data.items.len, self.cursorCol);
        }
    }

    pub fn onDown(self: *TextInputPayload) void {
        if (self.currentLine.next) |nextLine| {
            self.cursorRow += 1;
            self.currentLine = nextLine;
            self.cursorCol = @min(self.currentLine.data.items.len, self.cursorCol);
        }
    }

    pub fn onEnter(self: *TextInputPayload) !void {
        const newLine = try self.allocator.create(LinesType.Node);
        newLine.data = std.ArrayList(u32).init(self.allocator);
        newLine.prev = self.currentLine;
        newLine.next = self.currentLine.next;
        self.currentLine.next = newLine;
        self.currentLine = newLine;
        self.cursorRow += 1;
        self.cursorCol = 0;
        self.lineCount += 1;
    }

    pub fn onBackspace(self: *TextInputPayload) void {
        if (self.cursorCol > 0) {
            self.cursorCol -= 1;
            _ = self.currentLine.data.orderedRemove(self.cursorCol);
        } else if (self.currentLine.prev) |prevLine| {
            if (self.currentLine.next) |nextLine| {
                prevLine.next = nextLine;
                nextLine.prev = prevLine;
            }
            self.allocator.destroy(self.currentLine);
            self.lineCount -= 1;
            self.currentLine = prevLine;
            self.cursorRow -= 1;
            self.cursorCol = self.currentLine.data.items.len;
        }
    }

    pub fn onDelete(self: *TextInputPayload) void {
        if (self.cursorCol < self.currentLine.data.items.len) {
            _ = self.currentLine.data.orderedRemove(self.cursorCol);
        } // TODO: delete on empty line!
    }

    pub fn drawDebug(self: *const TextInputPayload, x: usize, y: usize) void {
        rl.drawText(
            rl.textFormat("Lines:%zu\nLength:%zu\nCursor: %d:%d", .{
                self.lineCount,
                self.currentLine.data.items.len,
                self.cursorRow,
                self.cursorCol,
            }),
            @intCast(x),
            @intCast(y),
            10,
            rl.Color.black,
        );
    }
};

pub const WidgetPayload = union(enum) {
    button: struct { text: [:0]const u8, fontSize: i32 },
    // let's assume single line text input only
    // todo: should we encode in UTF-16?
    text_input: TextInputPayload,
    grid: struct { rows: u8, cols: u8 },
};

const FONT_SPACING = 2.0;

pos: Vec2 = undefined,
size: Vec2 = undefined,
payload: WidgetPayload = undefined,
app: *Application,

pub fn layout(widget: *const @This()) void {
    _ = widget;
}

pub fn TextInput(allocator: std.mem.Allocator, app: *Application) !@This() {
    var lines = LinesType{};
    var emptyLine: *LinesType.Node = try allocator.create(LinesType.Node);
    emptyLine.data = std.ArrayList(u32).init(allocator);
    lines.append(emptyLine);
    return @This(){
        .payload = WidgetPayload{ .text_input = .{
            .fontSize = 80,
            .lines = lines,
            .lineCount = 1,
            .currentLine = lines.first.?,
            .cursorRow = 0,
            .cursorCol = 0,
            .allocator = allocator,
        } },
        .pos = .{ 10, 10 },
        .size = .{ 40, 40 },
        .app = app,
    };
}

pub fn draw(widget: *const @This(), allocator: std.mem.Allocator) !void {
    _ = allocator; // todo
    layout(widget);
    switch (widget.payload) {
        .button => |payload| {
            const textSize = rl.measureText(payload.text, payload.fontSize);
            rl.drawRectangle(
                @intFromFloat(widget.pos[0]),
                @intFromFloat(widget.pos[1]),
                textSize,
                payload.fontSize,
                rl.Color.light_gray,
            );
            rl.drawText(
                payload.text,
                @intFromFloat(widget.pos[0]),
                @intFromFloat(widget.pos[1]),
                payload.fontSize,
                rl.Color.red,
            );
        },
        .grid => |payload| {
            const rowsF = @as(f32, @floatFromInt(payload.rows));
            const colsF = @as(f32, @floatFromInt(payload.cols));
            const offsetX = widget.size[0] / rowsF;
            const offsetY = widget.size[1] / colsF;
            const sizeCell = .{ widget.size[0] / rowsF, widget.size[1] / colsF };
            for (0..payload.rows) |row| {
                for (0..payload.cols) |col| {
                    rl.drawRectangleLines(
                        @intFromFloat(widget.pos[0] + offsetX * @as(f32, @floatFromInt(row))),
                        @intFromFloat(widget.pos[1] + offsetY * @as(f32, @floatFromInt(col))),
                        @intFromFloat(sizeCell[0]),
                        @intFromFloat(sizeCell[1]),
                        rl.Color.light_gray,
                    );
                }
            }
        },
        .text_input => |payload| {
            const fontSize = widget.app.fontSize;
            // background:
            rl.drawRectangle(
                @intFromFloat(widget.pos[0]),
                @intFromFloat(widget.pos[1]),
                1000,
                fontSize * @as(i32, @intCast(payload.lineCount)),
                rl.Color.light_gray,
            );
            // text:
            const font = try widget.app.fontManager.getFont(@intCast(fontSize));
            const fontSizeFloat: f32 = @floatFromInt(fontSize);
            const spacing: comptime_float = 1.0;
            const fontWidth = rl.measureTextEx(font, "A", fontSizeFloat, spacing).x;

            var currentNode = payload.lines.first;
            var index: usize = 0;
            while (currentNode) |node| {
                const indexFloat: f32 = @floatFromInt(index);
                const y: f32 = widget.pos[1] + indexFloat * fontSizeFloat;
                rl.drawTextCodepoints(
                    font,
                    @ptrCast(node.data.items),
                    rl.Vector2{ .x = widget.pos[0], .y = y },
                    fontSizeFloat,
                    spacing,
                    rl.Color.red,
                );
                currentNode = node.next;
                index += 1;
            }

            // draw cursor:
            const cursorX: f32 = widget.pos[0] + (fontWidth + spacing) * @as(f32, @floatFromInt(payload.cursorCol));
            const cursorY: f32 = widget.pos[1] + fontSizeFloat * @as(f32, @floatFromInt(payload.cursorRow));
            rl.drawRectangle(
                @intFromFloat(cursorX),
                @intFromFloat(cursorY),
                4.0,
                fontSize,
                rl.Color.init(0, 0, 0, 160),
            );

            if (drawDebug) {
                payload.drawDebug(300, 300);
            }
        },
    }
}

pub fn defaultAction(self: *@This(), event: Event) !void {
    switch (self.payload) {
        .text_input => |*payload| {
            switch (event) {
                .charEvent => |character| {
                    // var buffer: [4]u8 = std.mem.zeroes([4]u8);
                    // const encoded = std.unicode.utf8Encode(character, &buffer) catch unreachable;
                    // try payload.codepoints.insertSlice(payload.cursorCol, buffer[0..encoded]);
                    try payload.currentLine.data.insert(payload.cursorCol, character);
                    payload.cursorCol += 1;
                },
                .keyEvent => |keyEvent| {
                    switch (keyEvent.code) {
                        .left => payload.onLeft(),
                        .right => payload.onRight(),
                        .down => payload.onDown(),
                        .up => payload.onUp(),
                        .enter => try payload.onEnter(),
                        .backspace => payload.onBackspace(),
                        .delete => payload.onDelete(),
                        else => {},
                    }
                },
                else => {},
            }
        },
        else => {
            // todo
        },
    }
}

pub fn deinit(self: *@This()) void {
    switch (self.payload) {
        .text_input => |*payload| {
            std.log.debug("lines deinit", .{});
            var it = payload.lines.first;
            while (it) |node| {
                node.data.deinit();
                it = node.next;
            }
        },
        else => {},
    }
}
