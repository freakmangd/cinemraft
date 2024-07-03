const std = @import("std");
const ztg = @import("zentig");
const rl = @import("zrl").rl;
const c = @import("init.zig");
const ChunkManager = c.ChunkManager;

const Tool = @This();

type: Type,
durability: u16,

pub var sprite_atlas: rl.Texture = undefined;
pub const inventory_sprite_size = 16;

pub fn setup() void {
    sprite_atlas = rl.LoadTexture("assets/tools.png");
}

pub fn init(tool_type: Type) Tool {
    return .{
        .type = tool_type,
        .durability = info.get(tool_type).max_durability,
    };
}

pub fn durabilityPercent(self: Tool) f32 {
    return ztg.math.divf32(self.durability, self.get(.max_durability)) catch 0;
}

pub fn get(self: Tool, comptime info_field: std.meta.FieldEnum(Info)) std.meta.FieldType(Info, info_field) {
    return @field(info.get(self.type), @tagName(info_field));
}

pub fn use(_: Tool, _: ChunkManager.HoveredBlockHit) void {}

pub const Type = enum {
    wood_shovel,
    wood_pickaxe,
    wood_axe,
    stone_shovel,
    stone_pickaxe,
    stone_axe,
};

const Info = struct {
    name: []const u8 = "Untitled",
    category: Category = .hand,
    material: Material = .wood,
    max_durability: u16 = 100,
    inventory_sprite_idx: @Vector(2, u16) = .{ 0, 0 },
};

pub const info = std.EnumArray(Type, Info).init(.{
    .wood_shovel = .{
        .name = "Wooden Shovel",
        .category = .shovel,
        .material = .wood,
        .max_durability = 60,
        .inventory_sprite_idx = .{ 1, 0 },
    },
    .wood_pickaxe = .{
        .name = "Wooden Pickaxe",
        .category = .pickaxe,
        .material = .wood,
        .max_durability = 50,
        .inventory_sprite_idx = .{ 2, 0 },
    },
    .wood_axe = .{
        .name = "Wooden Axe",
        .category = .axe,
        .material = .wood,
        .max_durability = 50,
        .inventory_sprite_idx = .{ 3, 0 },
    },
    .stone_shovel = .{
        .name = "Stone Shovel",
        .category = .shovel,
        .material = .stone,
        .max_durability = 180,
        .inventory_sprite_idx = .{ 1, 1 },
    },
    .stone_pickaxe = .{
        .name = "Stone Pickaxe",
        .category = .pickaxe,
        .material = .stone,
        .max_durability = 150,
        .inventory_sprite_idx = .{ 2, 1 },
    },
    .stone_axe = .{
        .name = "Stone Axe",
        .category = .axe,
        .material = .stone,
        .max_durability = 150,
        .inventory_sprite_idx = .{ 3, 1 },
    },
});

pub const Category = enum {
    hand,
    shovel,
    pickaxe,
    axe,
};

pub const Material = enum {
    wood,
    stone,
};

const Mts = std.EnumArray(Material, f32);

pub const mining_speed_mul = std.EnumArray(Category, Mts).init(.{
    .hand = Mts.initFill(1),
    .shovel = Mts.init(.{
        .wood = 2,
        .stone = 3,
    }),
    .pickaxe = Mts.init(.{
        .wood = 4,
        .stone = 5,
    }),
    .axe = Mts.init(.{
        .wood = 2,
        .stone = 3,
    }),
});
