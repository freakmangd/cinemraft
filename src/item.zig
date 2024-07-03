const std = @import("std");
const c = @import("init.zig");

pub const Item = union(enum) {
    block: Block.Type,
    tool: Tool,
    misc: Misc,

    pub const Block = c.Block;
    pub const Tool = @import("tool.zig");
    pub const Misc = @import("misc.zig").Misc;

    pub fn init(
        comptime outer_type: std.meta.Tag(Item),
        inner_type: switch (outer_type) {
            .block => Block.Type,
            .tool => Tool.Type,
            .misc => Misc,
        },
    ) Item {
        return switch (outer_type) {
            .block => .{ .block = inner_type },
            .tool => .{ .tool = Tool.init(inner_type) },
            .misc => .{ .misc = inner_type },
        };
    }

    pub fn maxStack(self: Item) u8 {
        return switch (self) {
            .block, .misc => 64,
            .tool => 1,
        };
    }

    pub fn eqlType(a: Item, b: Item) bool {
        const tag_a = std.meta.activeTag(a);
        const tag_b = std.meta.activeTag(b);

        if (tag_a != tag_b) return false;

        return switch (a) {
            .block => a.block == b.block,
            .tool => a.tool.type == b.tool.type,
            .misc => a.misc == b.misc,
        };
    }

    pub fn format(value: Item, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            inline .block, .misc => |t, tag| try writer.print("{s}({s})", .{ @tagName(tag), @tagName(t) }),
            .tool => |tool| try writer.print("tool({}, {d:.2}%)", .{ tool.type, tool.durabilityPercent() * 100 }),
        }
    }
};
