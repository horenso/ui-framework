pub const Vec2f = @Vector(2, f32);
pub const Vec4f = @Vector(4, f32);

pub const Vec2i = @Vector(2, i32);
pub const Vec4i = @Vector(4, i32);

pub fn isVec2fInsideVec4f(size: Vec4f, pos: Vec2f) bool {
    return (pos[0] >= size[0]) and
        (pos[0] <= size[0] + size[2]) and
        (pos[1] >= size[1]) and
        (pos[1] <= size[1] + size[3]);
}
