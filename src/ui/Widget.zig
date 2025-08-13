const std = @import("std");
const rl = @import("raylib");

const Application = @import("Application.zig");
const Event = @import("event.zig").Event;

const Vec2 = @Vector(2, f32);
const Vec4 = @Vector(4, f32);

pub const WidgetPayload = union(enum) {
    button: struct { text: [:0]const u8, fontSize: i32 },
    // let's assume single line text input only
    // todo: should we encode in UTF-16?
    text_input: struct {
        codepoints: std.ArrayList(u32),
        fontSize: i32,
        cursorRow: usize,
        cursorCol: usize,
    },
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
        .payload = WidgetPayload{ .text_input = .{
            .fontSize = 40,
            .codepoints = std.ArrayList(u32).init(allocator),
            .cursorRow = 0,
            .cursorCol = 0,
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
                fontSize,
                rl.Color.light_gray,
            );
            // text:
            const font = try widget.app.fontManager.getFont(@intCast(fontSize));
            const fontSizeFloat: f32 = @floatFromInt(fontSize);
            const spacing: comptime_float = 1.0;
            const fontWidth = rl.measureTextEx(font, "A", fontSizeFloat, spacing).x;
            rl.drawTextCodepoints(
                font,
                @ptrCast(payload.codepoints.items),
                rl.Vector2{ .x = widget.pos[0], .y = widget.pos[1] },
                fontSizeFloat,
                spacing,
                rl.Color.red,
            );

            // draw cursor:
            const cursorX: f32 = widget.pos[0] + (fontWidth + spacing) * @as(f32, @floatFromInt(payload.cursorCol));
            rl.drawRectangle(
                @intFromFloat(cursorX),
                @intFromFloat(widget.pos[1]),
                4.0,
                fontSize,
                rl.Color.init(0, 0, 0, 160),
            );
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
                    try payload.codepoints.insert(payload.cursorCol, character);
                    payload.cursorCol += 1;
                },
                .keyEvent => |keyEvent| {
                    if (keyEvent.code == .backspace and payload.cursorCol > 0) {
                        payload.cursorCol -= 1;
                        _ = payload.codepoints.orderedRemove(payload.cursorCol);
                    } else if (keyEvent.code == .delete and payload.codepoints.items.len > payload.cursorCol) {
                        _ = payload.codepoints.orderedRemove(payload.cursorCol);
                    } else if (keyEvent.code == .left and payload.cursorCol > 0) {
                        payload.cursorCol -= 1;
                    } else if (keyEvent.code == .right and payload.cursorCol < payload.codepoints.items.len) {
                        payload.cursorCol += 1;
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
            std.log.debug("codepoints deinit", .{});
            payload.codepoints.deinit();
        },
        else => {},
    }
}
