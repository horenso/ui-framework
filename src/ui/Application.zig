const std = @import("std");
const rl = @import("raylib");

const Widget = @import("Widget.zig");

const event = @import("event.zig");
const Event = event.Event;
const KeyCode = event.KeyCode;
const FontManager = @import("FontManager.zig");

const Config = struct {
    width: comptime_int,
    height: comptime_int,
    title: [:0]const u8,
};

const InputState = struct {
    leftMouseDown: bool = false,
    rightMouseDown: bool = false,
};

const KeyboardInputMode = enum {
    Key,
    Character,
};

keyboardInputMode: KeyboardInputMode = .Key,
inputState: InputState = InputState{},
inputQueue: std.ArrayList(Event),
allocator: std.mem.Allocator,

fontManager: FontManager,
fontSize: i32,

pub fn init(comptime config: Config, allocator: std.mem.Allocator) !@This() {
    rl.initWindow(config.width, config.height, config.title);
    rl.setTargetFPS(60);
    const app = @This(){
        .allocator = allocator,
        .inputQueue = std.ArrayList(Event).init(allocator),
        .fontManager = FontManager.init(allocator),
        .fontSize = 60,
    };
    return app;
}

pub fn deinit(self: *@This()) void {
    self.inputQueue.deinit();
    self.fontManager.deinit();
    rl.closeWindow();
}

pub fn draw(self: *@This(), parentWidget: *const Widget, allocator: std.mem.Allocator) !void {
    _ = self;

    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(rl.Color.white);
    try parentWidget.draw(allocator);
}

pub fn shouldClose(self: *@This()) bool {
    _ = self;
    return rl.windowShouldClose();
}

fn pollKey(self: *@This()) !void {
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
        else => return,
    };
    try self.inputQueue.append(Event{ .keyEvent = .{
        .code = keycode,
        .ctrl = rl.isKeyDown(rl.KeyboardKey.left_control) or rl.isKeyDown(rl.KeyboardKey.right_control),
        .shift = rl.isKeyDown(rl.KeyboardKey.left_shift) or rl.isKeyDown(rl.KeyboardKey.right_shift),
    } });
}

pub fn pollEvents(self: *@This()) !void {
    if (!self.inputState.leftMouseDown and rl.isMouseButtonDown(rl.MouseButton.left)) {
        self.inputState.leftMouseDown = true;
    }
    if (self.inputState.leftMouseDown and rl.isMouseButtonUp(rl.MouseButton.left)) {
        self.inputState.leftMouseDown = false;
    }

    // keyboard:
    if (self.keyboardInputMode == .Character) {
        const charPressed: u32 = @intCast(rl.getCharPressed());
        if (charPressed != 0) {
            _ = rl.getKeyPressed();
            try self.inputQueue.append(Event{ .charEvent = charPressed });
        } else {
            try pollKey(self);
            // const charScalar: u21 = @truncate(charPressed);
        }
    } else {
        try pollKey(self);
    }
}
