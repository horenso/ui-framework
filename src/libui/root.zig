const rl = @import("raylib");

const Vec2 = @Vector(2, f32);

pub const Widget = union(enum) {
    button: struct { pos: Vec2, size: Vec2, text: [:0]const u8, fontSize: i32 },
    grid: struct { pos: Vec2, size: Vec2, rows: u8, cols: u8 },
};

pub fn drawWidget(widget: *const Widget) void {
    switch (widget.*) {
        .button => |payload| {
            rl.drawRectangle(
                @intFromFloat(payload.pos[0]),
                @intFromFloat(payload.pos[1]),
                @intFromFloat(payload.size[0]),
                @intFromFloat(payload.size[1]),
                rl.Color.light_gray,
            );
            rl.drawText(
                payload.text,
                @intFromFloat(payload.pos[0]),
                @intFromFloat(payload.pos[1]),
                payload.fontSize,
                rl.Color.red,
            );
        },
        .grid => |payload| {
            const rowsF = @as(f32, @floatFromInt(payload.rows));
            const colsF = @as(f32, @floatFromInt(payload.cols));
            const offsetX = payload.size[0] / rowsF;
            const offsetY = payload.size[1] / colsF;
            const sizeCell = .{ payload.size[0] / rowsF, payload.size[1] / colsF };
            for (0..payload.rows) |row| {
                for (0..payload.cols) |col| {
                    rl.drawRectangleLines(
                        @intFromFloat(payload.pos[0] + offsetX * @as(f32, @floatFromInt(row))),
                        @intFromFloat(payload.pos[1] + offsetY * @as(f32, @floatFromInt(col))),
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
