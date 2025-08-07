pub const KeyCode = enum {
    // zig fmt: off
    a, b, c, d, e, f, g, h, i, j, k, l, m, 
    n, o, p, q, r, s, t, u, v, w, x, y, z,

    right, left, down, up, period,
    comma, space, escape, enter, tab,
    backspace, insert, delete,
    // zig fmt: on
};

pub const KeyEvent = struct {
    code: KeyCode,
    ctrl: bool,
    shift: bool,
};
pub const ClickEvent = struct {
    x: u16,
    y: u16,
    leftMouseButton: bool,
    middleMouseButton: bool,
    rightMouseButton: bool,
};
// Unicode character
pub const CharEvent = u32;

pub const Event = union(enum) {
    mouseEnterEvent: void,
    mouseLeaveEvent: void,
    clickEvent: ClickEvent,
    keyEvent: KeyEvent,
    charEvent: CharEvent,
};
