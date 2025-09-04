const std = @import("std");
const rl = @import("raylib");

const FontManager = @import("FontManager.zig");
const Widget = @import("./widget/Widget.zig");

const event = @import("event.zig");
const Event = event.Event;
const KeyCode = event.KeyCode;

const vec = @import("vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;

const Config = struct {
    width: comptime_int,
    height: comptime_int,
    title: [:0]const u8,
};

const InputState = struct {
    leftMouseDown: bool = false,
    rightMouseDown: bool = false,
};

inputState: InputState = InputState{},
inputQueue: std.ArrayList(Event),
allocator: std.mem.Allocator,

fontManager: FontManager,

pub fn init(comptime config: Config, allocator: std.mem.Allocator) !@This() {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(config.width, config.height, config.title);
    rl.setWindowMinSize(300, 300);
    rl.setMouseCursor(.ibeam);
    rl.setTargetFPS(60);
    const app = @This(){
        .allocator = allocator,
        .inputQueue = .empty,
        .fontManager = FontManager.init(allocator),
    };
    return app;
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    self.inputQueue.deinit(allocator);
    self.fontManager.deinit();
    rl.closeWindow();
}

pub fn layout(topWidget: *Widget) void {
    const width: f32 = @floatFromInt(rl.getScreenWidth());
    const height: f32 = @floatFromInt(rl.getScreenHeight());
    topWidget.layout(.{ width, height });
}

pub fn draw(self: *@This(), topWidget: *Widget) !void {
    _ = self;

    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(.sky_blue);
    try topWidget.draw();
}

pub fn shouldClose(self: *@This()) bool {
    _ = self;
    return rl.windowShouldClose();
}

fn pollKeys(self: *@This()) !void {
    while (true) {
        const key = rl.getKeyPressed();
        const keycode: KeyCode = switch (key) {
            .null => return,

            .a => .a,
            .b => .b,
            .c => .c,
            .d => .d,
            .e => .e,
            .f => .f,
            .g => .g,
            .h => .h,
            .i => .i,
            .j => .j,
            .k => .k,
            .l => .l,
            .m => .m,
            .n => .n,
            .o => .o,
            .p => .p,
            .q => .q,
            .r => .r,
            .s => .s,
            .t => .t,
            .u => .u,
            .v => .v,
            .w => .w,
            .x => .x,
            .y => .y,
            .z => .z,

            .zero => .num0,
            .one => .num1,
            .two => .num2,
            .three => .num3,
            .four => .num4,
            .five => .num5,
            .six => .num6,
            .seven => .num7,
            .eight => .num8,
            .nine => .num9,

            .left => .left,
            .right => .right,
            .up => .up,
            .down => .down,

            .backspace => .backspace,
            .delete => .delete,
            .space => .space,
            .enter => .enter,

            .period => .period,
            .comma => .comma,
            else => break,
        };

        const ctrl = rl.isKeyDown(rl.KeyboardKey.left_control) or rl.isKeyDown(rl.KeyboardKey.right_control);
        const shift = rl.isKeyDown(rl.KeyboardKey.left_shift) or rl.isKeyDown(rl.KeyboardKey.right_shift);
        const alt = rl.isKeyDown(rl.KeyboardKey.left_alt) or rl.isKeyDown(rl.KeyboardKey.right_alt);

        try self.inputQueue.append(self.allocator, .{ .keyEvent = .{
            .code = keycode,
            .char = @bitCast(rl.getCharPressed()),
            .ctrl = ctrl,
            .shift = shift,
            .alt = alt,
        } });
    }
}

pub fn pollEvents(self: *@This()) !void {
    if (!self.inputState.leftMouseDown and rl.isMouseButtonDown(rl.MouseButton.left)) {
        self.inputState.leftMouseDown = true;
    }
    if (self.inputState.leftMouseDown and rl.isMouseButtonUp(rl.MouseButton.left)) {
        self.inputState.leftMouseDown = false;
    }
    const mouseWheelMove = rl.getMouseWheelMoveV();
    if (mouseWheelMove.x != 0.0 or mouseWheelMove.y != 0.0) {
        try self.inputQueue.append(self.allocator, .{ .mouseWheelEvent = .{
            mouseWheelMove.x,
            mouseWheelMove.y,
        } });
    }

    if (rl.isMouseButtonPressed(.left)) {
        try self.inputQueue.append(self.allocator, .{ .clickEvent = .{
            .x = @intCast(rl.getMouseX()),
            .y = @intCast(rl.getMouseY()),
            .button = .left,
        } });
    } else if (rl.isMouseButtonPressed(.middle)) {
        try self.inputQueue.append(self.allocator, .{ .clickEvent = .{
            .x = @intCast(rl.getMouseX()),
            .y = @intCast(rl.getMouseY()),
            .button = .middle,
        } });
    } else if (rl.isMouseButtonPressed(.right)) {
        try self.inputQueue.append(self.allocator, .{ .clickEvent = .{
            .x = @intCast(rl.getMouseX()),
            .y = @intCast(rl.getMouseY()),
            .button = .right,
        } });
    }

    // keyboard:
    try pollKeys(self);
}
