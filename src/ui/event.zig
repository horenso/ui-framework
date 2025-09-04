const vec = @import("vec.zig");
const Vec2f = vec.Vec2f;

pub const KeyCode = enum {
    // zig fmt: off
    unknown,

    a, b, c, d, e, f, g, h, i, j, k, l, m, 
    n, o, p, q, r, s, t, u, v, w, x, y, z,

    num0, num1, num2, num3, num4,
    num5, num6, num7, num8, num9,

    right, left, down, up, period,
    comma, space, escape, enter, tab,
    backspace, insert, delete, plus, minus,
    // zig fmt: on
};

pub const KeyEvent = struct {
    code: KeyCode,
    char: ?u21,
    ctrl: bool,
    shift: bool,
    alt: bool,
    type: enum { Down, Pressed, Up },
};

pub const ClickEvent = struct {
    x: i32,
    y: i32,
    button: enum {
        left,
        middle,
        right,
    },
};
// Unicode character
pub const CharEvent = u32;

pub const Event = union(enum) {
    mouseEnterEvent: void,
    mouseLeaveEvent: void,
    clickEvent: ClickEvent,
    mouseWheelEvent: Vec2f,
    keyEvent: KeyEvent,
};
