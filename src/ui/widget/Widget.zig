const std = @import("std");
const rl = @import("raylib");

const Application = @import("../Application.zig");
const Event = @import("../event.zig").Event;

const Vec2 = @Vector(2, f32);
const Vec4 = @Vector(4, f32);

const drawDebug = true;

const TextInputPayload = @import("./TextInput.zig");
const LinesType = TextInputPayload.LinesType;

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
    return @This(){
        .payload = WidgetPayload{
            .text_input = try TextInputPayload.init(allocator),
        },
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
                fontSize * @as(i32, @intCast(payload.lines.len)),
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
                        .backspace => try payload.onBackspace(),
                        .delete => try payload.onDelete(),
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
            payload.deinit();
        },
        else => {},
    }
}
