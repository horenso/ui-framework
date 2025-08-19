const Event = @import("../event.zig").Event;

pub const Vec2 = @Vector(2, f32);
pub const Vec4 = @Vector(4, f32);

const Application = @import("../Application.zig");

ptr: *anyopaque,
vtable: *const VTable,

app: *Application,

pub const VTable = struct {
    deinit: *const fn (*anyopaque) void,
    draw: *const fn (*const anyopaque, app: *Application, position: Vec2, size: Vec2, offset: Vec2) anyerror!void,
    handleEvent: *const fn (*anyopaque, event: Event) anyerror!void,
};

pub fn deinit(self: @This()) void {
    self.vtable.deinit(self.ptr);
}

pub fn draw(self: @This(), position: Vec2, size: Vec2, offset: Vec2) anyerror!void {
    return self.vtable.draw(self.ptr, self.app, position, size, offset);
}

pub fn handleEvent(self: @This(), event: Event) anyerror!void {
    return self.vtable.handleEvent(self.ptr, event);
}
