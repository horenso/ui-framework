const rl = @import("raylib");

const Application = @import("../Application.zig");
const Event = @import("../event.zig").Event;

const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const Vec2i = vec.Vec2i;

ptr: *anyopaque,
vtable: *const VTable,

app: *Application,
size: Vec2f = .{ 0, 0 },

pub const VTable = struct {
    deinit: *const fn (*anyopaque) void,
    layout: *const fn (*anyopaque, size: Vec2f) void,
    draw: *const fn (*const anyopaque, app: *Application, position: Vec2f, size: Vec2f, offset: Vec2f) anyerror!void,
    /// Returns true if the event was handled, false otherwise.
    handleEvent: *const fn (*anyopaque, app: *Application, event: Event) anyerror!bool,
    getMaxContentSize: *const fn (*const anyopaque) Vec2f,
};

pub fn deinit(self: @This()) void {
    self.vtable.deinit(self.ptr);
}

pub fn getMaxContentSize(self: @This()) Vec2f {
    return self.vtable.getMaxContentSize(self.ptr);
}

pub fn layout(self: @This(), size: Vec2f) void {
    return self.vtable.layout(size);
}

pub fn draw(self: @This(), position: Vec2f, offset: Vec2f) anyerror!void {
    rl.beginScissorMode(
        @intFromFloat(position[0]),
        @intFromFloat(position[1]),
        @intFromFloat(self.size[0]),
        @intFromFloat(self.size[1]),
    );
    defer rl.endScissorMode();
    if (offset[0] != 0 or offset[1] != 0) {
        const camera = rl.Camera2D{
            .offset = .{ .x = offset[0], .y = offset[1] },
            .target = .{ .x = 0, .y = 0 },
            .rotation = 0.0,
            .zoom = 1.0,
        };
        camera.begin();
        defer camera.end();
        return self.vtable.draw(self.ptr, self.app, position, self.size, offset);
    } else {
        return self.vtable.draw(self.ptr, self.app, position, self.size, Vec2f{ 0, 0 });
    }
}

pub fn handleEvent(self: @This(), event: Event) anyerror!bool {
    return self.vtable.handleEvent(self.ptr, self.app, event);
}
