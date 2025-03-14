const std = @import("std");
const rl = @import("raylib");

const Widget = @import("Widget.zig");
const Event = @import("event.zig").Event;

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

pub fn init(comptime config: Config, allocator: std.mem.Allocator) @This() {
    rl.initWindow(config.width, config.height, config.title);
    rl.setTargetFPS(60);
    const app = @This(){
        .allocator = allocator,
        .inputQueue = std.ArrayList(Event).init(allocator),
    };
    // todo: ???
    return app;
}

pub fn close(self: @This()) void {
    self.inputQueue.deinit();
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

pub fn pollEvents(self: *@This()) !void {
    if (!self.inputState.leftMouseDown and rl.isMouseButtonDown(rl.MouseButton.left)) {
        self.inputState.leftMouseDown = true;
        std.log.debug("mouse button 0 down!", .{});
    }
    if (self.inputState.leftMouseDown and rl.isMouseButtonUp(rl.MouseButton.left)) {
        self.inputState.leftMouseDown = false;
        std.log.debug("mouse button 0 up!", .{});
        std.log.debug("mouse button 0 clicked!", .{});
    }

    // keyboard:
    while (true) {
        const key = rl.getKeyPressed();

        std.log.debug("{}", .{key});

        const keycode: Event.KeyCode = switch (key) {
            .null => break,

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

            .left => .left,
            .right => .right,
            .up => .up,
            .down => .down,

            .backspace => .backspace,
            .delete => .delete,
            .space => .space,

            .period => .period,
            .comma => .comma,

            else => {
                std.log.debug("IGNORING EVENT: {?}", .{key});
                continue;
            },
        };
        try self.inputQueue.append(Event{ .key = .{
            .code = keycode,
            .shift = rl.isKeyDown(rl.KeyboardKey.left_shift) or rl.isKeyDown(rl.KeyboardKey.right_shift),
        } });
    }
}
