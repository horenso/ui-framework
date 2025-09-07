const sdl = @cImport({
    @cInclude("SDL3/SDL_pixels.h");
});

r: u8,
g: u8,
b: u8,
a: u8,

pub fn init(r: u8, g: u8, b: u8, a: u8) @This() {
    return .{
        .r = r,
        .g = g,
        .b = b,
        .a = a,
    };
}

pub fn toSdlColor(comptime color: @This()) sdl.SDL_Color {
    return .{
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = color.a,
    };
}
