const std = @import("std");

const sdl = @import("./sdl.zig").sdl;

const ButtonType = event.ButtonType;
const Color = Renderer.Color;
const event = @import("event.zig");
const Event = event.Event;
const FontManager = @import("FontManager.zig");
const KeyCode = event.KeyCode;
const KeyEvent = event.KeyEvent;
const KeyEventType = event.KeyEventType;
const Renderer = @import("Renderer.zig");
const TextEvent = event.TextEvent;
const Widget = @import("./widget/Widget.zig");

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

const SdlState = struct {
    window: *sdl.SDL_Window,
    cursor: ?*sdl.SDL_Cursor,
};

_shouldClose: bool = false,

inputState: InputState = .{},
inputQueue: std.ArrayList(Event) = .empty,
sdlState: SdlState,
allocator: std.mem.Allocator,

fontManager: FontManager,
renderer: Renderer,

pub fn init(comptime config: Config, allocator: std.mem.Allocator) error{InitFailure}!@This() {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        return error.InitFailure;
    }

    const window = sdl.SDL_CreateWindow(
        config.title,
        config.width,
        config.height,
        sdl.SDL_WINDOW_OPENGL | sdl.SDL_WINDOW_RESIZABLE,
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
    const cursor = sdl.SDL_CreateSystemCursor(sdl.SDL_SYSTEM_CURSOR_TEXT);
    if (cursor != null) {
        _ = sdl.SDL_SetCursor(cursor);
    }

    return .{
        .allocator = allocator,
        .inputQueue = .empty,
        .fontManager = FontManager.init(allocator) catch return error.InitFailure,
        .renderer = Renderer.init(sdlRenderer),
        .sdlState = .{
            .window = window,
            .cursor = cursor,
        },
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    self.inputQueue.deinit(allocator);
    self.fontManager.deinit(allocator);

    if (self.sdlState.cursor) |cursor| {
        sdl.SDL_DestroyCursor(cursor);
    }

    self.renderer.deinit();
    sdl.SDL_DestroyWindow(self.sdlState.window);

    sdl.SDL_Quit();
}

pub fn layout(self: *@This(), topWidget: *Widget) void {
    var width: c_int = 0;
    var height: c_int = 0;
    if (!sdl.SDL_GetWindowSize(self.sdlState.window, &width, &height)) {
        std.log.debug("Could not get window dimensions!", .{});
    }
    topWidget.layout(.{ @floatFromInt(width), @floatFromInt(height) });
}

pub fn draw(self: *@This(), topWidget: *Widget) !void {
    self.renderer.clear(Color.init(255, 255, 255, 255));
    try topWidget.draw(&self.renderer);
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
                const btn: event.ButtonType = switch (sdlEvent.button.button) {
                    sdl.SDL_BUTTON_LEFT => .left,
                    sdl.SDL_BUTTON_MIDDLE => .middle,
                    sdl.SDL_BUTTON_RIGHT => .right,
                    else => continue,
                };
                try self.inputQueue.append(self.allocator, .{ .mouseClick = .{
                    .pos = .{ sdlEvent.button.x, sdlEvent.button.y },
                    .button = btn,
                } });
                self.inputState.leftMouseDown = (btn == .left);
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_UP => {
                if (sdlEvent.button.button == sdl.SDL_BUTTON_LEFT) {
                    self.inputState.leftMouseDown = false;
                }
            },
            sdl.SDL_EVENT_TEXT_INPUT => {
                const cStringText = sdlEvent.text.text;
                const utf8Viewer = try std.unicode.Utf8View.init(cStringText[0..std.mem.len(cStringText)]);
                var it = utf8Viewer.iterator();
                while (it.nextCodepoint()) |codepoint| {
                    try self.inputQueue.append(self.allocator, .{ .text = .{ .char = codepoint } });
                }
            },
            else => {},
        }
    }
}
