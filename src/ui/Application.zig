const std = @import("std");

const sdl = @import("./sdl.zig").sdl;

const ButtonType = eventImport.ButtonType;
const Color = @import("Color.zig");
const eventImport = @import("event.zig");
const Event = eventImport.Event;
const EventHandler = @import("EventHandler.zig");
const FontManager = @import("FontManager.zig");
const KeyCode = eventImport.KeyCode;
const KeyEvent = eventImport.KeyEvent;
const KeyEventType = eventImport.KeyEventType;
const Renderer = @import("Renderer.zig");
const TextEvent = eventImport.TextEvent;
const Widget = @import("./widget/Widget.zig");

const vec = @import("vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;

const Config = struct {
    width: comptime_int,
    height: comptime_int,
    title: [:0]const u8,
};

const Pointer = enum {
    default,
    text,
    move,
};

const SdlPointers = struct {
    default: *sdl.SDL_Cursor,
    text: *sdl.SDL_Cursor,
    move: *sdl.SDL_Cursor,
};

const SdlState = struct {
    window: *sdl.SDL_Window,
    pointers: SdlPointers,
};

/// For debugging. Draws the widget in the middle of the widget, making the overflow visible.
const DEBUG_VIRTUAL_WINDOW = true;
const DEBUG_VIRTUAL_WINDOW_OFFSET = 50;

_sdlState: SdlState,
_shouldClose: bool = false,

inputQueue: std.ArrayList(Event) = .empty,
allocator: std.mem.Allocator,

currentPointer: Pointer = .default,
nextPointer: Pointer = .default,

fontManager: FontManager,
renderer: Renderer,

/// If present is be called before each event.
/// If it returns true the function "caught" the event
/// and it will not be handed to the parent widget
eventHandler: ?EventHandler = null,

pub fn init(comptime config: Config, allocator: std.mem.Allocator) error{InitFailure}!@This() {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        return error.InitFailure;
    }

    const window = sdl.SDL_CreateWindow(
        config.title,
        config.width,
        config.height,
        sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE,
    ) orelse return error.InitFailure;

    _ = sdl.SDL_SetWindowMinimumSize(window, 300, 300);
    _ = sdl.SDL_StartTextInput(window);

    const sdlRenderer = sdl.SDL_CreateRenderer(window, null) orelse {
        std.log.err("SDL_CreateRenderer() Error: {s}", .{sdl.SDL_GetError()});
        return error.InitFailure;
    };

    if (!sdl.SDL_SetRenderDrawBlendMode(sdlRenderer, sdl.SDL_BLENDMODE_BLEND)) {
        std.log.warn("Could not enable blend mode: {s}", .{sdl.SDL_GetError()});
    }

    if (!sdl.SDL_SetRenderVSync(sdlRenderer, 1)) {
        std.log.warn("Could not enable VSync: {s}", .{sdl.SDL_GetError()});
    }

    // Set the I-beam cursor
    const pointers: SdlPointers = .{
        .default = sdl.SDL_CreateSystemCursor(sdl.SDL_SYSTEM_CURSOR_DEFAULT) orelse return error.InitFailure,
        .text = sdl.SDL_CreateSystemCursor(sdl.SDL_SYSTEM_CURSOR_TEXT) orelse return error.InitFailure,
        .move = sdl.SDL_CreateSystemCursor(sdl.SDL_SYSTEM_CURSOR_MOVE) orelse return error.InitFailure,
    };

    return .{
        .allocator = allocator,
        .inputQueue = .empty,
        .fontManager = FontManager.init(allocator) catch return error.InitFailure,
        .renderer = Renderer.init(sdlRenderer),
        ._sdlState = .{
            .window = window,
            .pointers = pointers,
        },
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    self.inputQueue.deinit(allocator);
    self.fontManager.deinit(allocator);

    _ = sdl.SDL_DestroyCursor(self._sdlState.pointers.default);
    _ = sdl.SDL_DestroyCursor(self._sdlState.pointers.text);
    _ = sdl.SDL_DestroyCursor(self._sdlState.pointers.move);

    self.renderer.deinit();
    sdl.SDL_DestroyWindow(self._sdlState.window);

    sdl.SDL_Quit();
}

pub fn getWindowSize(self: *@This()) Vec2f {
    var width: c_int = 0;
    var height: c_int = 0;
    if (!sdl.SDL_GetWindowSizeInPixels(self._sdlState.window, &width, &height)) {
        std.log.warn("Could not get window dimensions!", .{});
    }
    return .{ @floatFromInt(width), @floatFromInt(height) };
}

pub fn setWindowTitle(self: *@This(), title: []const u8) void {
    if (!sdl.SDL_SetWindowTitle(self._sdlState.window, @ptrCast(title))) {
        std.log.warn("Could not set window title: {s}", .{sdl.SDL_GetError()});
    }
}

pub fn layout(self: *@This(), topWidget: Widget) void {
    const size = self.getWindowSize();

    if (DEBUG_VIRTUAL_WINDOW) {
        topWidget.layout(size - @as(Vec2f, @splat(2 * DEBUG_VIRTUAL_WINDOW_OFFSET)));
    } else {
        topWidget.layout(size);
    }
}

pub fn handleHover(self: *@This(), topWidget: Widget) bool {
    const size = self.getWindowSize();

    var mousePos: Vec2f = undefined;
    _ = sdl.SDL_GetMouseState(&mousePos[0], &mousePos[1]);

    const windowBounce: Vec4f = if (DEBUG_VIRTUAL_WINDOW) .{
        DEBUG_VIRTUAL_WINDOW_OFFSET,
        DEBUG_VIRTUAL_WINDOW_OFFSET,
        size[0] - 2 * DEBUG_VIRTUAL_WINDOW_OFFSET,
        size[1] - 2 * DEBUG_VIRTUAL_WINDOW_OFFSET,
    } else .{
        0,
        0,
        size[0],
        size[1],
    };

    self.setPointer(.default);

    if (vec.isVec2fInsideVec4f(windowBounce, mousePos)) {
        if (DEBUG_VIRTUAL_WINDOW) {
            mousePos -= @as(Vec2f, @splat(DEBUG_VIRTUAL_WINDOW_OFFSET));
        }
        topWidget.handleHover(mousePos);
    }
    return self.currentPointer != self.nextPointer;
}

pub fn draw(self: *@This(), topWidget: Widget) !void {
    if (self.currentPointer != self.nextPointer) {
        switch (self.nextPointer) {
            .default => _ = sdl.SDL_SetCursor(self._sdlState.pointers.default),
            .text => _ = sdl.SDL_SetCursor(self._sdlState.pointers.text),
            .move => _ = sdl.SDL_SetCursor(self._sdlState.pointers.move),
        }
        self.currentPointer = self.nextPointer;
    }
    self.renderer.clear(Color.init(255, 255, 255, 255));

    if (DEBUG_VIRTUAL_WINDOW) {
        self.renderer.offset += @splat(DEBUG_VIRTUAL_WINDOW_OFFSET);
        defer self.renderer.offset -= @splat(DEBUG_VIRTUAL_WINDOW_OFFSET);
        try topWidget.draw(&self.renderer);
    } else {
        try topWidget.draw(&self.renderer);
    }

    self.renderer.present();
}

pub fn shouldClose(self: *@This()) bool {
    return self._shouldClose;
}

fn handleKeyEvent(self: *@This(), sdlScancode: sdl.SDL_Scancode, sdlEventType: u32, modstate: u16) !void {
    const keyCode: KeyCode = switch (sdlScancode) {
        sdl.SDL_SCANCODE_A => .a,
        sdl.SDL_SCANCODE_B => .b,
        sdl.SDL_SCANCODE_C => .c,
        sdl.SDL_SCANCODE_D => .d,
        sdl.SDL_SCANCODE_E => .e,
        sdl.SDL_SCANCODE_F => .f,
        sdl.SDL_SCANCODE_G => .g,
        sdl.SDL_SCANCODE_H => .h,
        sdl.SDL_SCANCODE_I => .i,
        sdl.SDL_SCANCODE_J => .j,
        sdl.SDL_SCANCODE_K => .k,
        sdl.SDL_SCANCODE_L => .l,
        sdl.SDL_SCANCODE_M => .m,
        sdl.SDL_SCANCODE_N => .n,
        sdl.SDL_SCANCODE_O => .o,
        sdl.SDL_SCANCODE_P => .p,
        sdl.SDL_SCANCODE_Q => .q,
        sdl.SDL_SCANCODE_R => .r,
        sdl.SDL_SCANCODE_S => .s,
        sdl.SDL_SCANCODE_T => .t,
        sdl.SDL_SCANCODE_U => .u,
        sdl.SDL_SCANCODE_V => .v,
        sdl.SDL_SCANCODE_W => .w,
        sdl.SDL_SCANCODE_X => .x,
        sdl.SDL_SCANCODE_Y => .y,
        sdl.SDL_SCANCODE_Z => .z,

        sdl.SDL_SCANCODE_0 => .num0,
        sdl.SDL_SCANCODE_1 => .num1,
        sdl.SDL_SCANCODE_2 => .num2,
        sdl.SDL_SCANCODE_3 => .num3,
        sdl.SDL_SCANCODE_4 => .num4,
        sdl.SDL_SCANCODE_5 => .num5,
        sdl.SDL_SCANCODE_6 => .num6,
        sdl.SDL_SCANCODE_7 => .num7,
        sdl.SDL_SCANCODE_8 => .num8,
        sdl.SDL_SCANCODE_9 => .num9,

        sdl.SDL_SCANCODE_LEFT => .left,
        sdl.SDL_SCANCODE_RIGHT => .right,
        sdl.SDL_SCANCODE_UP => .up,
        sdl.SDL_SCANCODE_DOWN => .down,

        sdl.SDL_SCANCODE_BACKSPACE => .backspace,
        sdl.SDL_SCANCODE_DELETE => .delete,
        sdl.SDL_SCANCODE_SPACE => .space,
        sdl.SDL_SCANCODE_RETURN => .enter,
        sdl.SDL_SCANCODE_PERIOD => .period,
        sdl.SDL_SCANCODE_COMMA => .comma,

        sdl.SDL_SCANCODE_HOME => .home,
        sdl.SDL_SCANCODE_END => .end,

        else => .unknown,
    };

    const ctrl = (modstate & sdl.SDL_KMOD_CTRL) != 0;
    const shift = (modstate & sdl.SDL_KMOD_SHIFT) != 0;
    const alt = (modstate & sdl.SDL_KMOD_ALT) != 0;

    const eventType: KeyEventType = switch (sdlEventType) {
        sdl.SDL_EVENT_KEY_DOWN => .down,
        sdl.SDL_EVENT_KEY_UP => .up,
        else => .pressed,
    };

    var newEvent: Event = .{
        .key = .{
            .code = keyCode,
            .ctrl = ctrl,
            .shift = shift,
            .alt = alt,
            .type = eventType,
        },
    };

    try self.inputQueue.append(self.allocator, newEvent);
    if (eventType == .up) {
        newEvent.key.type = .pressed;
        try self.inputQueue.append(self.allocator, newEvent);
    }
}

pub fn pollEvents(self: *@This()) !void {
    var sdlEvent: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&sdlEvent)) {
        switch (sdlEvent.type) {
            sdl.SDL_EVENT_QUIT => {
                self._shouldClose = true;
            },
            sdl.SDL_EVENT_KEY_DOWN, sdl.SDL_EVENT_KEY_UP => {
                try self.handleKeyEvent(
                    sdlEvent.key.scancode,
                    sdlEvent.type,
                    sdlEvent.key.mod,
                );
            },
            sdl.SDL_EVENT_MOUSE_WHEEL => {
                try self.inputQueue.append(self.allocator, .{
                    .mouseWheel = .{
                        sdlEvent.wheel.x,
                        sdlEvent.wheel.y,
                    },
                });
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                const btn: eventImport.ButtonType = switch (sdlEvent.button.button) {
                    sdl.SDL_BUTTON_LEFT => .left,
                    sdl.SDL_BUTTON_MIDDLE => .middle,
                    sdl.SDL_BUTTON_RIGHT => .right,
                    else => continue,
                };
                var pos: Vec2f = .{
                    sdlEvent.button.x,
                    sdlEvent.button.y,
                };
                if (DEBUG_VIRTUAL_WINDOW) {
                    const size = self.getWindowSize();
                    if (!vec.isVec2fInsideVec4f(.{
                        DEBUG_VIRTUAL_WINDOW_OFFSET,
                        DEBUG_VIRTUAL_WINDOW_OFFSET,
                        size[0] - 2 * DEBUG_VIRTUAL_WINDOW_OFFSET,
                        size[1] - 2 * DEBUG_VIRTUAL_WINDOW_OFFSET,
                    }, pos)) {
                        return;
                    }
                    pos -= @as(Vec2f, @splat(DEBUG_VIRTUAL_WINDOW_OFFSET));
                }
                try self.inputQueue.append(self.allocator, .{ .mouseClick = .{
                    .pos = pos,
                    .button = btn,
                } });
            },
            sdl.SDL_EVENT_TEXT_INPUT => {
                const cStringText = sdlEvent.text.text;
                const utf8Viewer = try std.unicode.Utf8View.init(cStringText[0..std.mem.len(cStringText)]);
                var it = utf8Viewer.iterator();
                while (it.nextCodepoint()) |codepoint| {
                    try self.inputQueue.append(self.allocator, .{ .text = .{ .char = codepoint } });
                }
            },
            sdl.SDL_EVENT_MOUSE_MOTION => {
                var pos: Vec2f = .{
                    sdlEvent.motion.x,
                    sdlEvent.motion.y,
                };
                if (DEBUG_VIRTUAL_WINDOW) {
                    const size = self.getWindowSize();
                    if (!vec.isVec2fInsideVec4f(.{
                        DEBUG_VIRTUAL_WINDOW_OFFSET,
                        DEBUG_VIRTUAL_WINDOW_OFFSET,
                        size[0] - 2 * DEBUG_VIRTUAL_WINDOW_OFFSET,
                        size[1] - 2 * DEBUG_VIRTUAL_WINDOW_OFFSET,
                    }, pos)) {
                        return;
                    }
                    pos -= @as(Vec2f, @splat(DEBUG_VIRTUAL_WINDOW_OFFSET));
                }
                try self.inputQueue.append(self.allocator, .{ .mouseMotion = .{
                    .pos = pos,
                    .delta = .{ sdlEvent.motion.xrel, sdlEvent.motion.yrel },
                } });
            },
            sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => {
                std.log.debug("resize: {any}", .{sdlEvent.window});
                try self.inputQueue.append(self.allocator, .resize);
            },
            else => {},
        }
    }
}

pub fn setPointer(self: *@This(), pointer: Pointer) void {
    self.nextPointer = pointer;
}

pub fn startEventLoop(self: *@This(), allocator: std.mem.Allocator, parentWidget: Widget) !void {
    var frames: u64 = 0;

    const targetFps = 60;
    const targetFrameMs: u32 = 1000 / targetFps;

    var redraws: enum { skip, redraw, redrawTwoFrames } = .redraw;

    while (!self.shouldClose()) {
        const frameStart = sdl.SDL_GetTicks();

        try self.pollEvents();
        while (self.inputQueue.pop()) |event| {
            if (event == .resize) {
                redraws = .redrawTwoFrames;
                continue;
            }

            if (self.eventHandler) |handler| {
                if (try handler.handleEvent(event)) {
                    redraws = .redraw;
                    continue;
                }
            }
            if (try parentWidget.handleEvent(event)) {
                redraws = .redraw;
                continue;
            }
        }

        if (self.handleHover(parentWidget) and redraws != .redrawTwoFrames) {
            redraws = .redraw;
        }

        while (redraws != .skip) {
            frames +%= 1;
            const title = try std.fmt.allocPrint(allocator, "Frames: {}", .{frames});
            defer allocator.free(title);
            self.setWindowTitle(title);

            self.layout(parentWidget);
            try self.draw(parentWidget);
            redraws = if (redraws == .redrawTwoFrames) .redraw else .skip;
        }

        const frameEnd = sdl.SDL_GetTicks() - frameStart;
        if (frameEnd < targetFrameMs) {
            const waitTime = targetFrameMs - frameEnd;
            sdl.SDL_Delay(@truncate(waitTime));
        }
    }
}
