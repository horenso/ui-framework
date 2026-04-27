const std = @import("std");

const Color = @import("../Color.zig");
const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;

pub const Texture = *anyopaque;

pub const VTable = struct {
    deinit: *const fn (*anyopaque) void,
    setClip: *const fn (*anyopaque, offset: Vec2f, clip: Vec2f) void,
    clear: *const fn (*anyopaque, Color) void,
    present: *const fn (*anyopaque) void,
    outline: *const fn (*anyopaque, rect: Vec4f, offset: Vec2f, Color) void,
    fillRect: *const fn (*anyopaque, rect: Vec4f, offset: Vec2f, Color) void,
    fillRectPattern: *const fn (*anyopaque, rect: Vec4f, offset: Vec2f) void,
    line: *const fn (*anyopaque, p1: Vec2f, p2: Vec2f, offset: Vec2f, Color) void,
    createTexture: *const fn (*anyopaque, w: i32, h: i32) Texture,
    drawCharacter: *const fn (*anyopaque, std.mem.Allocator, u32, *anyopaque, pos: Vec2f, offset: Vec2f, Color) void,
};

ptr: *anyopaque,
vtable: *const VTable,
offset: Vec2f = .{ 0, 0 },
_clip: Vec2f = .{ 0, 0 },

pub fn deinit(self: @This()) void {
    self.vtable.deinit(self.ptr);
}

pub fn setClip(self: *@This(), clip: Vec2f) void {
    self._clip = clip;
    self.vtable.setClip(self.ptr, self.offset, clip);
}

pub fn clear(self: @This(), color: Color) void {
    self.vtable.clear(self.ptr, color);
}

pub fn present(self: @This()) void {
    self.vtable.present(self.ptr);
}

pub fn outline(self: @This(), rect: Vec4f, color: Color) void {
    self.vtable.outline(self.ptr, rect, self.offset, color);
}

pub fn fillRect(self: @This(), rect: Vec4f, color: Color) void {
    self.vtable.fillRect(self.ptr, rect, self.offset, color);
}

pub fn fillRectPattern(self: @This(), rect: Vec4f) void {
    self.vtable.fillRectPattern(self.ptr, rect, self.offset);
}

pub fn line(self: @This(), p1: Vec2f, p2: Vec2f, color: Color) void {
    self.vtable.line(self.ptr, p1, p2, self.offset, color);
}

pub fn createTexture(self: @This(), w: i32, h: i32) Texture {
    return self.vtable.createTexture(self.ptr, w, h);
}

pub fn drawCharacter(
    self: @This(),
    allocator: std.mem.Allocator,
    codepoint: u32,
    fontAtlas: *anyopaque,
    pos: Vec2f,
    color: Color,
) void {
    self.vtable.drawCharacter(self.ptr, allocator, codepoint, fontAtlas, pos, self.offset, color);
}
