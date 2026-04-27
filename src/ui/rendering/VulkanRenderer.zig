const std = @import("std");

const Renderer = @import("Renderer.zig");
const Color = @import("../Color.zig");
const vec = @import("../vec.zig");
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;

pub fn init() @This() {
    return .{};
}

pub fn renderer(self: *@This()) Renderer {
    return .{ .ptr = self, .vtable = &vtable };
}

const vtable: Renderer.VTable = .{
    .deinit = deinitImpl,
    .setClip = setClipImpl,
    .clear = clearImpl,
    .present = presentImpl,
    .outline = outlineImpl,
    .fillRect = fillRectImpl,
    .fillRectPattern = fillRectPatternImpl,
    .line = lineImpl,
    .createTexture = createTextureImpl,
    .drawCharacter = drawCharacterImpl,
};

fn deinitImpl(_: *anyopaque) void {}

fn setClipImpl(_: *anyopaque, _: Vec2f, _: Vec2f) void {
    @panic("VulkanRenderer: not implemented");
}

fn clearImpl(_: *anyopaque, _: Color) void {
    @panic("VulkanRenderer: not implemented");
}

fn presentImpl(_: *anyopaque) void {
    @panic("VulkanRenderer: not implemented");
}

fn outlineImpl(_: *anyopaque, _: Vec4f, _: Vec2f, _: Color) void {
    @panic("VulkanRenderer: not implemented");
}

fn fillRectImpl(_: *anyopaque, _: Vec4f, _: Vec2f, _: Color) void {
    @panic("VulkanRenderer: not implemented");
}

fn fillRectPatternImpl(_: *anyopaque, _: Vec4f, _: Vec2f) void {
    @panic("VulkanRenderer: not implemented");
}

fn lineImpl(_: *anyopaque, _: Vec2f, _: Vec2f, _: Vec2f, _: Color) void {
    @panic("VulkanRenderer: not implemented");
}

fn createTextureImpl(_: *anyopaque, _: i32, _: i32) Renderer.Texture {
    @panic("VulkanRenderer: not implemented");
}

fn drawCharacterImpl(_: *anyopaque, _: std.mem.Allocator, _: u32, _: *anyopaque, _: Vec2f, _: Vec2f, _: Color) void {
    @panic("VulkanRenderer: not implemented");
}
