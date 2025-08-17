const std = @import("std");
const rl = @import("raylib");

pub const LinesType = std.DoublyLinkedList(std.ArrayList(u32));

lines: LinesType, // TODO! lines.len is not correct!
fontSize: i32,
currentLine: *LinesType.Node,
cursorRow: usize,
cursorCol: usize,
allocator: std.mem.Allocator, // TODO: do I need it?

pub fn init(allocator: std.mem.Allocator) !@This() {
    var lines = LinesType{};
    var emptyLine: *LinesType.Node = try allocator.create(LinesType.Node);
    emptyLine.data = std.ArrayList(u32).init(allocator);
    lines.append(emptyLine);
    return .{
        .fontSize = 80,
        .lines = lines,
        .currentLine = emptyLine,
        .cursorRow = 0,
        .cursorCol = 0,
        .allocator = allocator,
    };
}

pub fn loadFromFile(self: *@This()) void {
    _ = self;
}

pub fn writeToFile(self: *@This(), path: []const u8) void {
    _ = self;
    _ = path;
}

pub fn onLeft(self: *@This()) void {
    if (self.cursorCol > 0) {
        self.cursorCol -= 1;
    } else if (self.currentLine.prev) |prevLine| {
        self.cursorRow -= 1;
        self.currentLine = prevLine;
        self.cursorCol = self.currentLine.data.items.len;
    }
}

pub fn onRight(self: *@This()) void {
    if (self.cursorCol < self.currentLine.data.items.len) {
        self.cursorCol += 1;
    } else if (self.currentLine.next) |nextLine| {
        self.cursorRow += 1;
        self.currentLine = nextLine;
        self.cursorCol = 0;
    }
}

pub fn onUp(self: *@This()) void {
    if (self.currentLine.prev) |prevLine| {
        self.cursorRow -= 1;
        self.currentLine = prevLine;
        self.cursorCol = @min(self.currentLine.data.items.len, self.cursorCol);
    }
}

pub fn onDown(self: *@This()) void {
    if (self.currentLine.next) |nextLine| {
        self.cursorRow += 1;
        self.currentLine = nextLine;
        self.cursorCol = @min(self.currentLine.data.items.len, self.cursorCol);
    }
}

pub fn onEnter(self: *@This()) !void {
    const newLine = try self.allocator.create(LinesType.Node);
    newLine.data = std.ArrayList(u32).init(self.allocator);
    self.lines.insertAfter(self.currentLine, newLine);
    self.currentLine = newLine;
    self.cursorRow += 1;
    self.cursorCol = 0;
}

pub fn onBackspace(self: *@This()) void {
    if (self.cursorCol > 0) {
        self.cursorCol -= 1;
        _ = self.currentLine.data.orderedRemove(self.cursorCol);
    } else if (self.currentLine.prev != null) {
        self.lines.remove(self.currentLine);
        self.allocator.destroy(self.currentLine);
        self.cursorRow -= 1;
        self.cursorCol = self.currentLine.data.items.len;
    }
}

pub fn onDelete(self: *@This()) void {
    if (self.cursorCol < self.currentLine.data.items.len) {
        _ = self.currentLine.data.orderedRemove(self.cursorCol);
    } // TODO: delete on empty line!
}

pub fn drawDebug(self: *const @This(), x: usize, y: usize) void {
    rl.drawText(
        rl.textFormat("Lines:%zu\nLength:%zu\nCursor: %d:%d", .{
            self.lines.len,
            self.currentLine.data.items.len,
            self.cursorRow,
            self.cursorCol,
        }),
        @intCast(x),
        @intCast(y),
        10,
        rl.Color.black,
    );
}
