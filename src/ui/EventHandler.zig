const Event = @import("event.zig").Event;

ptr: *anyopaque,
_handler: *const fn (self: *anyopaque, event: Event) anyerror!bool,

pub fn handleEvent(self: @This(), event: Event) !bool {
    return self._handler(self.ptr, event);
}
