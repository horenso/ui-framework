const Application = @import("libui/Application.zig");
const root = @import("libui/root.zig");

pub fn main() anyerror!void {
    Application.init(.{ .width = 800, .height = 600, .title = "Hello, world!" });
    defer Application.close();

    const button = root.Widget{
        .payload = root.WidgetPayload{ .button = .{
            .fontSize = 40,
            .text = "Hello, button!",
        } },
        .pos = .{ 10, 10 },
        .size = .{ 30, 30 },
    };
    // const grid = root.Widget{ .grid = .{
    //     .pos = .{ 10, 10 },
    //     .size = .{ 500, 500 },
    //     .cols = 3,
    //     .rows = 3,
    // } };

    Application.draw(&button);
}
