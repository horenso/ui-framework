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

pub const KeyEventType = enum { down, pressed, up };

pub const KeyEvent = struct {
    code: KeyCode,
    ctrl: bool,
    shift: bool,
    alt: bool,
    type: KeyEventType,
};

pub const TextEvent = struct {
    char: u32,
};

pub const ButtonType = enum {
    left,
    middle,
    right,
};

pub const ClickEvent = struct {
    pos: Vec2f,
    button: ButtonType,
};

pub const Event = union(enum) {
    mouseClick: ClickEvent,
    mouseWheel: Vec2f,
    key: KeyEvent,
    text: TextEvent,
};
