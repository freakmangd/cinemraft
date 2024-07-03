const std = @import("std");
const ztg = @import("zentig");
const zrl = @import("zrl");
const rl = zrl.rl;
const c = @import("init.zig");

const Chat = @This();

text_box: std.ArrayListUnmanaged(u8) = .{},
messages: std.ArrayListUnmanaged([]const u8) = .{},

is_open: bool = false,
alpha: f32 = 0,

pub fn deinit(self: *Chat, alloc: std.mem.Allocator) void {
    self.text_box.deinit(alloc);

    for (self.messages.items) |msg| {
        alloc.free(msg);
    }
    self.messages.deinit(alloc);
}

pub fn open(self: *Chat) void {
    self.is_open = true;
    self.alpha = 5;
}

pub fn close(self: *Chat, alloc: std.mem.Allocator) !void {
    self.is_open = false;
    self.text_box.clearAndFree(alloc);
}

pub fn update(self: *Chat, com: ztg.Commands, alloc: std.mem.Allocator, player_pos: ztg.Vec3, sender: *c.Player) !bool {
    if (!self.is_open) {
        self.alpha = @max(self.alpha - rl.GetFrameTime(), 0);
        return false;
    }

    const char: u8 = @intCast(rl.GetCharPressed());

    if (char != rl.KEY_NULL) {
        try self.text_box.append(alloc, char);
    } else if (rl.IsKeyPressed(rl.KEY_BACKSPACE) and self.text_box.items.len > 0) {
        _ = self.text_box.swapRemove(self.text_box.items.len - 1);
    } else if (rl.IsKeyPressed(rl.KEY_ENTER)) {
        if (self.text_box.items.len > 0) {
            try self.sendMessage(com, alloc, player_pos, sender, self.text_box.items);
        }

        return true;
    } else if (rl.IsKeyPressed(rl.KEY_ESCAPE)) return true;

    return false;
}

fn sendMessage(self: *Chat, com: ztg.Commands, alloc: std.mem.Allocator, player_pos: ztg.Vec3, sender: *c.Player, text: []const u8) !void {
    if (text[0] != '/') {
        const text_dup = try std.mem.concat(alloc, u8, &.{ sender.name, ": ", self.text_box.items });
        errdefer alloc.free(text_dup);

        try self.messages.append(alloc, text_dup);
        return;
    }

    var iter = std.mem.tokenizeScalar(u8, text[1..], ' ');

    const cmd = std.meta.stringToEnum(Command, iter.next() orelse return) orelse return;

    switch (cmd) {
        .give => {
            const item_name = iter.next() orelse return;
            const item: c.Item = blk: {
                for (std.enums.values(c.Block.Type)) |t| {
                    if (std.mem.eql(u8, item_name, @tagName(t))) {
                        break :blk .{ .block = t };
                    }
                }
                for (std.enums.values(c.Item.Tool.Type)) |t| {
                    if (std.mem.eql(u8, item_name, @tagName(t))) {
                        break :blk c.Item.init(.tool, t);
                    }
                }
                for (std.enums.values(c.Item.Misc)) |t| {
                    if (std.mem.eql(u8, item_name, @tagName(t))) {
                        break :blk .{ .misc = t };
                    }
                }
                std.log.err("{s} is not an item", .{item_name});
                // NOTE: removing this line doesnt compile error
                return;
            };

            const count = blk: {
                const count_str = iter.next() orelse break :blk 1;
                break :blk std.fmt.parseInt(u8, count_str, 10) catch |err| {
                    std.log.err("cannot parse count for give: {}", .{err});
                    return;
                };
            };

            _ = try sender.inventory.giveAll(com, player_pos, item, count);
        },
    }
}

const Command = enum {
    give,
};

pub fn drawGui(self: Chat) void {
    const width = 400;
    const padding = 10;

    const height = rl.GetScreenHeight();
    var y: c_int = height - 25 - padding;

    const alpha = @min(1, self.alpha);

    if (self.is_open) {
        rl.DrawRectangle(10, y, width, height - y - padding, rl.ColorAlpha(rl.BLACK, 0.5 * alpha));
        c.drawText(self.text_box.items, padding * 2, y, 20, rl.ColorAlpha(rl.WHITE, alpha));
    }
    y -= 25 + padding;

    const backing_y = y - 25 * 6;
    rl.DrawRectangle(10, backing_y, width, height - backing_y - padding - (25 + padding), rl.ColorAlpha(rl.BLACK, 0.5 * alpha));

    for (0..@min(7, self.messages.items.len)) |i| {
        c.drawText(self.messages.items[self.messages.items.len - i - 1], padding * 2, y, 20, rl.ColorAlpha(rl.WHITE, alpha));
        y -= 25;
    }
}
