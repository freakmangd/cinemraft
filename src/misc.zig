const std = @import("std");
const rl = @import("zrl").rl;

pub const Misc = enum {
    stick,
    apple,
    wheat,
    sugar,
    plum,

    pub var sprite_atlas: rl.Texture = undefined;
    pub const inventory_sprite_size = 16;

    pub fn setup() void {
        sprite_atlas = rl.LoadTexture("assets/misc_items.png");
    }

    pub fn get(self: Misc, comptime info_field: std.meta.FieldEnum(Info)) std.meta.FieldType(Info, info_field) {
        return @field(info.get(self), @tagName(info_field));
    }
};

const Info = struct {
    name: []const u8 = "Untitled",
    inventory_sprite_idx: @Vector(2, u16) = .{ 0, 0 },
};

pub const info = std.EnumArray(Misc, Info).init(.{
    .stick = .{
        .name = "Stick",
        .inventory_sprite_idx = .{ 1, 0 },
    },
    .apple = .{
        .inventory_sprite_idx = .{ 2, 0 },
    },
    .sugar = .{
        .inventory_sprite_idx = .{ 4, 0 },
    },
    .wheat = .{
        .inventory_sprite_idx = .{ 5, 0 },
    },
    .plum = .{
        .inventory_sprite_idx = .{ 0, 1 },
    },
});
