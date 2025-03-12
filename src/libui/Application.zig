const rl = @import("raylib");

const Widget = @import("root.zig").Widget;
const drawWidget = @import("root.zig").drawWidget;

const std = @import("std");

const Config = struct {
    width: comptime_int,
    height: comptime_int,
    title: [:0]const u8,
};

pub fn init(comptime config: Config) void {
    rl.initWindow(config.width, config.height, config.title);
    rl.setTargetFPS(60);
}

pub fn close() void {
    rl.closeWindow();
}

pub fn draw(widget: *const Widget) void {
    var inputState = InputState{};

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);

        drawWidget(widget);

        pollEvents(&inputState);
    }
}

const InputState = struct {
    leftMouseDown: bool = false,
    rightMouseDown: bool = false,
};

pub fn pollEvents(state: *InputState) void {
    if (!state.leftMouseDown and rl.isMouseButtonDown(rl.MouseButton.left)) {
        state.leftMouseDown = true;
        std.log.debug("mouse button 0 down!", .{});
    }
    if (state.leftMouseDown and rl.isMouseButtonUp(rl.MouseButton.left)) {
        state.leftMouseDown = false;
        std.log.debug("mouse button 0 up!", .{});
        std.log.debug("mouse button 0 clicked!", .{});
    }
    // if (rl.isMouseButtonUp(rl.MouseButton.left)) {
    //     std.log.debug("mouse button 0 up", .{});
    // }
}
