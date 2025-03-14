const std = @import("std");
const rl = @import("raylib");

const Event = @import("event.zig").Event;

const Vec2 = @Vector(2, f32);
const Vec4 = @Vector(4, f32);

pub const WidgetPayload = union(enum) {
    button: struct { text: [:0]const u8, fontSize: i32 },
    // let's assume single line text input only
    text_input: struct { text: std.ArrayList(u8), fontSize: i32, cursorPos: usize },
    grid: struct { rows: u8, cols: u8 },
};

const FONT_SPACING = 2.0;

pos: Vec2 = undefined,
size: Vec2 = undefined,
payload: WidgetPayload = undefined,

pub fn layout(widget: *const @This()) void {
    _ = widget;
}

pub fn draw(widget: *const @This(), allocator: std.mem.Allocator) !void {
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
            const cursor_size: i32 = 4;

            const info = rl.getGlyphInfo(try rl.getFontDefault(), 'a');
            _ = info;
            const text_c_string = try allocator.dupeZ(u8, payload.text.items);
            defer allocator.free(text_c_string);
            const partial_text_c_string = try allocator.dupeZ(u8, payload.text.items[0..payload.cursorPos]);
            defer allocator.free(partial_text_c_string);

            const text_size = rl.measureText(text_c_string, payload.fontSize) + cursor_size * 2;
            const cursor_pos = rl.measureText(partial_text_c_string, payload.fontSize);

            // background:
            rl.drawRectangle(
                @as(i32, @intFromFloat(widget.pos[0])) + cursor_size,
                @intFromFloat(widget.pos[1]),
                text_size,
                payload.fontSize,
                rl.Color.light_gray,
            );
            // text:
            rl.drawText(
                text_c_string,
                @as(i32, @intFromFloat(widget.pos[0])) + cursor_size,
                @intFromFloat(widget.pos[1]),
                payload.fontSize,
                rl.Color.red,
            );
            // draw cursor:
            rl.drawRectangle(
                @as(i32, @intFromFloat(widget.pos[0] + @as(f32, @floatFromInt(cursor_pos)))) + cursor_size / 2,
                @intFromFloat(widget.pos[1]),
                cursor_size,
                payload.fontSize,
                rl.Color.init(0, 0, 0, 160),
            );
        },
    }
}

pub fn defaultAction(self: *@This(), event: Event) !void {
    switch (self.payload) {
        .text_input => |*payload| {
            switch (event) {
                .key => |keyEvent| {
                    const maybe_char = keyEvent.toCharacter();
                    if (maybe_char) |char| {
                        try payload.text.insert(payload.cursorPos, char);
                        payload.cursorPos += 1;
                    } else if (keyEvent.code == .backspace and payload.cursorPos > 0) {
                        payload.cursorPos -= 1;
                        _ = payload.text.orderedRemove(payload.cursorPos);
                    } else if (keyEvent.code == .delete and payload.text.items.len > payload.cursorPos) {
                        _ = payload.text.orderedRemove(payload.cursorPos);
                    } else if (keyEvent.code == .left and payload.cursorPos > 0) {
                        payload.cursorPos -= 1;
                    } else if (keyEvent.code == .right and payload.cursorPos < payload.text.items.len) {
                        payload.cursorPos += 1;
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
