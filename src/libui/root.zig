const rl = @import("raylib");

const Vec2 = @Vector(2, f32);
const Vec4 = @Vector(4, f32);

pub const WidgetPayload = union(enum) {
    button: struct { text: [:0]const u8, fontSize: i32 },
    grid: struct { rows: u8, cols: u8 },
};

pub const Widget = struct {
    pos: Vec2,
    size: Vec2,
    payload: WidgetPayload,
};

pub const Style = struct {};

const FONT_SPACING = 2.0;

pub fn layout(widget: *const Widget) void {
    _ = widget;
}

pub fn drawWidget(widget: *const Widget) void {
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
    }
}

pub const Event = union(enum) {
    mouseEnter: void,
    mouseLeave: void,
    click: void,
};
