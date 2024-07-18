const std = @import("std");
const ztg = @import("zentig");
const zrl = @import("zrl");
const rlight = @import("rlights.zig");
const rl = zrl.rl;
const c = @import("init.zig");
const Chunk = c.Chunk;

const Block = @This();

pub const size = 8;

// TODO(mods): move all of this into BlockInfo, which in turn
// should be a Resource that can be added upon
pub var material: rl.Material = undefined;
pub var shader: rl.Shader = undefined;

pub var block_sprite_atlas: rl.Texture2D = undefined;
pub const block_sprite_size = 32;

var models: std.StringHashMapUnmanaged(rl.Model) = .{};

pub var snapshot_tex: rl.RenderTexture = undefined;
const snap_size = 42;

type: Type = .none,
data: *anyopaque = undefined,

exposed: std.bit_set.IntegerBitSet(6) = std.bit_set.IntegerBitSet(6).initEmpty(),
rotation: Rotation = .{},

pub fn include(wb: *ztg.WorldBuilder) void {
    wb.addSystems(.{
        .init = setup,
        .deinit = cleanup,
    });
}

pub fn SHIT() void {
    const snapshot_cam = rl.Camera3D{
        .up = zrl.vec3up,
        .fovy = 23,
        .target = zrl.vec3(0.5, 0, 0.5),
        .position = zrl.vec3(-3, 2.8, -3),
    };

    const block_snapshot_mesh = rl.GenMeshCube(1, 1, 1);
    const snapshot_transform = rl.MatrixTranslate(0, 0.5, 0);
    rl.BeginDrawing();
    defer rl.EndDrawing();

    rl.ClearBackground(rl.BLACK);

    {
        rl.BeginMode3D(snapshot_cam);
        defer rl.EndMode3D();

        rl.DrawMesh(block_snapshot_mesh, rl.LoadMaterialDefault(), snapshot_transform);
    }

    rl.DrawRectangle(0, 0, 50, 50, rl.RED);
}

fn drawGui() void {
    rl.DrawTexture(snapshot_tex.texture, 0, 0, rl.WHITE);
}

fn setup(alloc: std.mem.Allocator) !void {
    block_sprite_atlas = rl.LoadTexture("assets/block_art.png");

    shader = rl.LoadShader(
        "assets/shaders/block_vertex.glsl",
        "assets/shaders/block_fragment.glsl",
    );
    shader.locs[rl.SHADER_LOC_MATRIX_MVP] = rl.GetShaderLocation(shader, "mvp");
    shader.locs[rl.SHADER_LOC_VECTOR_VIEW] = rl.GetShaderLocation(shader, "viewPos");
    shader.locs[rl.SHADER_LOC_MATRIX_MODEL] = rl.GetShaderLocationAttrib(shader, "instanceTransform");

    material = rl.LoadMaterialDefault();
    material.shader = shader;
    material.maps[rl.MATERIAL_MAP_DIFFUSE].texture = block_sprite_atlas;

    var snapshot_material = rl.LoadMaterialDefault();
    snapshot_material.maps[rl.MATERIAL_MAP_DIFFUSE].texture = block_sprite_atlas;

    snapshot_tex = rl.LoadRenderTexture(@intCast(snap_size * std.enums.values(Type).len), snap_size);
    const snapshot_cam = rl.Camera3D{
        .up = zrl.vec3up,
        .fovy = 23,
        .target = zrl.vec3(0.5, 0, 0.5),
        .position = zrl.vec3(-3, 2.8, -3),
    };

    const snapshot_transform = rl.MatrixTranslate(0, 0.5, 0);
    for (std.enums.values(Type), 0..) |t, i| {
        if (t.get(.model_type) == .model) continue;

        const block_snap_tex: rl.RenderTexture = rl.LoadRenderTexture(snap_size, snap_size);
        defer rl.UnloadRenderTexture(block_snap_tex);

        const block_snapshot_mesh = try genBlockPreviewMesh(alloc, @splat(1), t);
        defer unloadPreviewMesh(alloc, block_snapshot_mesh);

        {
            rl.BeginTextureMode(block_snap_tex);
            defer rl.EndTextureMode();

            rl.ClearBackground(rl.BLANK);

            {
                rl.BeginMode3D(snapshot_cam);
                defer rl.EndMode3D();

                rl.DrawMesh(block_snapshot_mesh, snapshot_material, snapshot_transform);
            }
        }

        {
            rl.BeginTextureMode(snapshot_tex);
            defer rl.EndTextureMode();

            rl.DrawTexturePro(
                block_snap_tex.texture,
                .{
                    .width = @floatFromInt(block_snap_tex.texture.width),
                    .height = @floatFromInt(block_snap_tex.texture.height),
                },
                .{ .x = @floatFromInt(snap_size * i), .width = snap_size, .height = snap_size },
                .{},
                0,
                rl.WHITE,
            );
        }
    }
}

pub fn cleanup(alloc: std.mem.Allocator) void {
    models.deinit(alloc);
}

pub fn getTransform(pos: Position) rl.Matrix {
    return rl.MatrixTranslate(
        @as(f32, @floatFromInt(pos.x * Block.size)) + Block.size / 4,
        @as(f32, @floatFromInt(pos.y * Block.size)) + Block.size / 4,
        @as(f32, @floatFromInt(pos.z * Block.size)) + Block.size / 4,
    );
}

pub const PlacedOn = struct { Block, Side };

pub fn onPlace(self: *Block, alloc: std.mem.Allocator, block_pos: Position, place_opts: c.ChunkManager.PlaceOpts) !void {
    switch (self.type) {
        .chest => {
            const dir_to_placer: Side = blk: {
                const placer_pos = place_opts.placer_pos orelse break :blk .north;
                const dir_to_player: ztg.Vec3 = block_pos.toWorldZ().directionTo(placer_pos);

                if (dir_to_player.x > 0) {
                    break :blk .east;
                } else if (dir_to_player.x < 0) {
                    break :blk .west;
                } else if (dir_to_player.z > 0) {
                    break :blk .north;
                } else if (dir_to_player.z < 0) {
                    break :blk .south;
                }

                break :blk .north;
            };

            self.rotation = Rotation.fromSide(dir_to_placer);

            const cd = try alloc.create(Type.ChestData);
            cd.* = .{};
            self.data = cd;
        },
        else => {},
    }
}

pub fn onUse(self: Block, gui: *c.Player.Gui) void {
    switch (self.type) {
        .crafting_table => {
            c.Player.Gui.crafting_table_gui.open(gui);
        },
        .chest => {
            c.Player.Gui.chest_gui.open(gui, @ptrCast(@alignCast(self.data)));
        },
        else => {},
    }
}

pub fn onBreak(self: Block, pos: Position, alloc: std.mem.Allocator, rand: std.Random, com: ztg.Commands) !void {
    switch (self.type) {
        .none => {},
        .leaves => {
            if (rand.float(f32) < 0.1)
                try drop(.{ .misc = .apple }, pos, com);
        },
        .urple_leaves => {
            if (rand.float(f32) < 0.1)
                try drop(.{ .misc = .plum }, pos, com);
        },
        .grass => try drop(.{ .block = .dirt }, pos, com),
        .stone => try drop(.{ .block = .cobblestone }, pos, com),
        .chest => {
            const chest_data: *Type.ChestData = @ptrCast(@alignCast(self.data));
            for (chest_data.items) |slot| {
                if (slot == .filled) _ = try c.ItemPickup.spawn(
                    com,
                    pos.toWorldZ().add(ztg.splat3(size / 2)),
                    ztg.Vec3.randomOnUnitSphere(rand).mul(10),
                    slot.filled.count,
                    slot.filled.item,
                );
            }
            try drop(.{ .block = .chest }, pos, com);
        },
        else => |t| try drop(.{ .block = t }, pos, com),
    }
    self.deinit(alloc);
}

fn drop(item: c.Item, pos: Position, com: ztg.Commands) !void {
    _ = try c.ItemPickup.spawn(
        com,
        pos.toWorldZ().add(ztg.splat3(Block.size / 2)),
        .{},
        1,
        item,
    );
}

pub fn deinit(self: Block, alloc: std.mem.Allocator) void {
    switch (self.type) {
        .chest => alloc.destroy(@as(*Type.ChestData, @ptrCast(@alignCast(self.data)))),
        else => {},
    }
}

pub const Position = struct {
    x: i64 = 0,
    y: usize = 0,
    z: i64 = 0,

    pub inline fn init(x: i64, y: usize, z: i64) Position {
        return .{ .x = x, .y = y, .z = z };
    }

    pub inline fn eql(a: Position, b: Position) bool {
        return a.x == b.x and a.y == b.y and a.z == b.z;
    }

    pub inline fn toWorld(self: Position) rl.Vector3 {
        return .{
            .x = @floatFromInt(self.x * size),
            .y = @floatFromInt(self.y * size),
            .z = @floatFromInt(self.z * size),
        };
    }

    pub inline fn toWorldZ(self: Position) ztg.Vec3 {
        return ztg.vec3(self.x * size, self.y * size, self.z * size);
    }

    pub inline fn toWorldV(self: Position) @Vector(3, f32) {
        return .{
            @floatFromInt(self.x * size),
            @floatFromInt(self.y * size),
            @floatFromInt(self.z * size),
        };
    }

    pub inline fn fromVector(v: @Vector(3, i64)) Position {
        return .{ .x = v[0], .y = @intCast(@max(0, v[1])), .z = v[2] };
    }

    pub inline fn fromWorld(world_pos: rl.Vector3) Position {
        return .{
            .x = @intFromFloat(world_pos.x / Block.size),
            .y = @intFromFloat(@max(0, world_pos.y / Block.size)),
            .z = @intFromFloat(world_pos.z / Block.size),
        };
    }

    test fromWorld {
        const pos = zrl.vec3(16.5, -100, 3.5);
        try std.testing.expectEqual(Position{ .x = 2, .y = 0, .z = 0 }, Position.fromWorld(pos));
    }

    pub inline fn toIndex(self: Position) Index {
        return .{
            .x = @intCast(@mod(self.x, Chunk.horizontal_size)),
            .y = @intCast(self.y),
            .z = @intCast(@mod(self.z, Chunk.horizontal_size)),
        };
    }

    test toIndex {
        const pos = Position{ .x = -2, .y = 0, .z = 2 };
        try std.testing.expectEqual(Index{ .x = Chunk.horizontal_size - 2, .y = 0, .z = 2 }, pos.toIndex());
    }

    pub inline fn toChunkPos(self: Position) Chunk.Position {
        return .{
            .x = @intCast(@divFloor(self.x, Chunk.horizontal_size)),
            .z = @intCast(@divFloor(self.z, Chunk.horizontal_size)),
        };
    }

    pub inline fn shift(self: Position, dir: Side, by: u32) Position {
        return switch (dir) {
            .top => .{ .x = self.x, .y = self.y + by, .z = self.z },
            .bottom => .{ .x = self.x, .y = self.y - by, .z = self.z },
            .north => .{ .x = self.x, .y = self.y, .z = self.z + by },
            .south => .{ .x = self.x, .y = self.y, .z = self.z - by },
            .west => .{ .x = self.x - by, .y = self.y, .z = self.z },
            .east => .{ .x = self.x + by, .y = self.y, .z = self.z },
        };
    }

    pub inline fn shiftV(self: Position, by: @Vector(3, i32)) Position {
        if (self.y == 0 and by[1] < 0) return self;

        const result_y = if (by[1] >= 0)
            self.y + @as(usize, @intCast(by[1]))
        else
            self.y - @as(usize, @intCast(-by[1]));

        return .{ .x = self.x + by[0], .y = result_y, .z = self.z + by[2] };
    }

    pub fn format(value: Position, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("({}, {}, {})", .{ value.x, value.y, value.z });
    }
};

pub const Index = packed struct(u24) {
    x: u8,
    y: u8,
    z: u8,

    pub inline fn init(x: anytype, y: anytype, z: anytype) Index {
        return .{
            .x = ztg.math.toInt(u8, x),
            .y = ztg.math.toInt(u8, y),
            .z = ztg.math.toInt(u8, z),
        };
    }

    pub fn fromUsize(x: usize, y: usize, z: usize) Index {
        return .{ .x = @intCast(x), .y = @intCast(y), .z = @intCast(z) };
    }

    pub fn toPosition(self: Index, parent_chunk: Chunk.Position) Position {
        return .{
            .x = self.x + parent_chunk.x * Chunk.horizontal_size,
            .y = self.y,
            .z = self.z + parent_chunk.z * Chunk.horizontal_size,
        };
    }

    pub fn toWorld(self: Index, parent_chunk: Chunk.Position) rl.Vector3 {
        return .{
            .x = @floatFromInt(self.x * Block.size + parent_chunk.x * Chunk.to_world_space),
            .y = @floatFromInt(self.y * Block.size),
            .z = @floatFromInt(self.z * Block.size + parent_chunk.z * Chunk.to_world_space),
        };
    }

    pub fn toWorldV(self: Index, parent_chunk: Chunk.Position) @Vector(3, f32) {
        return .{
            @floatFromInt(self.x * Block.size + parent_chunk.x * Chunk.to_world_space),
            @floatFromInt(self.y * Block.size),
            @floatFromInt(self.z * Block.size + parent_chunk.z * Chunk.to_world_space),
        };
    }

    pub fn toVector(self: Index) @Vector(3, u8) {
        return .{ self.x, self.y, self.z };
    }

    pub fn fromWorld(world_pos: rl.Vector3) Index {
        return .{
            .x = @intFromFloat(@mod(world_pos.x, Chunk.to_world_space)),
            .y = @intFromFloat(world_pos.y / Block.size),
            .z = @intFromFloat(@mod(world_pos.z, Chunk.to_world_space)),
        };
    }

    pub fn shift(self: Index, dir: Side, by: u8) Index {
        return switch (dir) {
            .top => .{ .x = self.x, .y = self.y + by, .z = self.z },
            .bottom => .{ .x = self.x, .y = self.y - by, .z = self.z },
            .north => .{ .x = self.x, .y = self.y, .z = self.z + by },
            .south => .{ .x = self.x, .y = self.y, .z = self.z - by },
            .west => .{ .x = self.x - by, .y = self.y, .z = self.z },
            .east => .{ .x = self.x + by, .y = self.y, .z = self.z },
        };
    }

    pub fn addVector(self: Index, v: @Vector(3, u8)) Index {
        return .{
            .x = self.x + v[0],
            .y = self.y + v[1],
            .z = self.z + v[2],
        };
    }
};

pub const Type = enum {
    none,
    grass,
    dirt,
    stone,
    cobblestone,
    wood_plank,
    wood,
    bedrock,
    leaves,
    crafting_table,
    testicle,
    apple_pie,
    chest,
    urple_wood,
    urple_leaves,
    urple_wood_plank,

    pub fn get(self: Type, comptime field: std.meta.FieldEnum(BlockInfo)) std.meta.FieldType(BlockInfo, field) {
        return @field(block_info.get(self), @tagName(field));
    }

    pub const ChestData = struct {
        items: [c.Inventory.len]c.Inventory.Slot = .{.empty} ** c.Inventory.len,
    };
};

pub const Side = enum(u8) {
    top = 0,
    bottom = 1,
    west = 2,
    east = 3,
    north = 4,
    south = 5,

    pub const no_top_bottom = [_]Side{
        .west,
        .east,
        .north,
        .south,
    };

    pub fn int(self: Side) u8 {
        return @intFromEnum(self);
    }

    pub fn opposite(self: Side) Side {
        return switch (self) {
            .west => .east,
            .east => .west,
            .north => .south,
            .south => .north,
            .top => .bottom,
            .bottom => .top,
        };
    }

    pub fn toVector(self: Side) rl.Vector3 {
        // zig fmt: off
        return switch (self) {
            .east   => zrl.vec3( 1,  0,  0 ),
            .west   => zrl.vec3(-1,  0,  0 ),
            .top    => zrl.vec3( 0,  1,  0 ),
            .bottom => zrl.vec3( 0, -1,  0 ),
            .north  => zrl.vec3( 0,  0,  1 ),
            .south  => zrl.vec3( 0,  0, -1 ),
        };
        // zig fmt: on
    }

    // idk lmao
    pub fn fromVector(vec: rl.Vector3) Side {
        if (vec.x == 1) {
            return .east;
        } else if (vec.x == -1) {
            return .west;
        } else if (vec.y == 1) {
            return .top;
        } else if (vec.y == -1) {
            return .bottom;
        } else if (vec.z == 1) {
            return .north;
        } else if (vec.z == -1) {
            return .south;
        }
        @panic("uh");
    }
};

pub const Rotation = struct {
    wn_rots: u8 = 0,
    nt_rots: u8 = 0,

    pub fn init(wn: u8, nt: u8) Rotation {
        return .{ .wn_rots = wn, .nt_rots = nt };
    }

    pub fn fromSide(side: Side) Rotation {
        return switch (side) {
            .north => .{},
            .south => init(2, 0),
            .east => init(1, 0),
            .west => init(3, 0),
            .top => init(0, 1),
            .bottom => init(0, 3),
        };
    }
};

pub fn loadModel(alloc: std.mem.Allocator, name: [:0]const u8) !rl.Model {
    const gop = try models.getOrPut(alloc, name);
    if (!gop.found_existing) {
        gop.value_ptr.* = rl.LoadModel(name);
    }
    return gop.value_ptr.*;
}

const TextureIndexFromSide = std.EnumArray(Side, @Vector(2, usize));

pub const BlockInfo = struct {
    model_type: union(enum) {
        block: TextureIndexFromSide,
        model: [:0]const u8,
    },
    average_color: @Vector(3, f32) = .{ 255, 255, 255 },
    mining_speed: f32,
    breaking_tool: c.Item.Tool.Category = .hand,
    can_use: bool = false,
};

pub const block_info = std.EnumArray(Type, BlockInfo).init(.{
    .none = .{
        .model_type = .{ .block = TextureIndexFromSide.initFill(.{ 0, 3 }) },
        .average_color = .{ 255, 255, 255 },
        .mining_speed = 0,
        .breaking_tool = .hand,
    },
    .grass = .{
        .model_type = .{ .block = TextureIndexFromSide.init(.{
            .top = .{ 2, 0 },
            .bottom = .{ 3, 0 },
            .west = .{ 1, 0 },
            .east = .{ 1, 0 },
            .north = .{ 1, 0 },
            .south = .{ 1, 0 },
        }) },
        .average_color = .{ 102, 155, 49 },
        .mining_speed = 1,
        .breaking_tool = .shovel,
    },
    .dirt = .{
        .model_type = .{ .block = TextureIndexFromSide.initFill(.{ 3, 0 }) },
        .average_color = .{ 153, 90, 49 },
        .mining_speed = 1,
        .breaking_tool = .shovel,
    },
    .wood = .{
        .model_type = .{ .block = TextureIndexFromSide.init(.{
            .top = .{ 3, 1 },
            .bottom = .{ 3, 1 },
            .west = .{ 2, 1 },
            .east = .{ 2, 1 },
            .north = .{ 2, 1 },
            .south = .{ 2, 1 },
        }) },
        .average_color = .{ 170, 84, 53 },
        .mining_speed = 2,
        .breaking_tool = .axe,
    },
    .wood_plank = .{
        .model_type = .{ .block = TextureIndexFromSide.initFill(.{ 1, 1 }) },
        .average_color = .{ 245, 170, 86 },
        .mining_speed = 1.5,
        .breaking_tool = .axe,
    },
    .leaves = .{
        .model_type = .{ .block = TextureIndexFromSide.initFill(.{ 0, 2 }) },
        .average_color = .{ 95, 195, 92 },
        .mining_speed = 0.3,
        .breaking_tool = .hand,
    },
    .stone = .{
        .model_type = .{ .block = TextureIndexFromSide.initFill(.{ 0, 1 }) },
        .average_color = .{ 114, 114, 114 },
        .mining_speed = 5,
        .breaking_tool = .pickaxe,
    },
    .cobblestone = .{
        .model_type = .{ .block = TextureIndexFromSide.initFill(.{ 3, 2 }) },
        .average_color = .{ 114, 114, 114 },
        .mining_speed = 4,
        .breaking_tool = .pickaxe,
    },
    .bedrock = .{
        .model_type = .{ .block = TextureIndexFromSide.initFill(.{ 2, 2 }) },
        .average_color = .{ 0, 0, 0 },
        .mining_speed = std.math.inf(f32),
        .breaking_tool = .hand,
    },
    .testicle = .{
        .model_type = .{ .block = TextureIndexFromSide.initFill(.{ 1, 2 }) },
        .average_color = .{ 239, 193, 113 },
        .mining_speed = 0.69,
        .breaking_tool = .hand,
    },
    .crafting_table = .{
        .model_type = .{ .block = TextureIndexFromSide.init(.{
            .top = .{ 2, 3 },
            .bottom = .{ 3, 1 },
            .west = .{ 1, 3 },
            .east = .{ 1, 3 },
            .north = .{ 1, 3 },
            .south = .{ 1, 3 },
        }) },
        .average_color = .{ 245, 170, 86 },
        .mining_speed = 1.75,
        .breaking_tool = .axe,
        .can_use = true,
    },
    .apple_pie = .{
        .model_type = .{ .model = "assets/models/apple_pie.obj" },
        .average_color = .{ 245, 170, 86 },
        .mining_speed = 1,
        .breaking_tool = .hand,
        .can_use = true,
    },
    .chest = .{
        .model_type = .{ .block = TextureIndexFromSide.init(.{
            .top = .{ 4, 2 },
            .bottom = .{ 4, 2 },
            .west = .{ 4, 3 },
            .east = .{ 4, 3 },
            .south = .{ 4, 3 },
            .north = .{ 3, 3 },
        }) },
        .mining_speed = 4,
        .breaking_tool = .axe,
        .can_use = true,
    },
    .urple_wood = .{
        .model_type = .{ .block = TextureIndexFromSide.init(.{
            .top = .{ 1, 4 },
            .bottom = .{ 1, 4 },
            .west = .{ 0, 4 },
            .east = .{ 0, 4 },
            .south = .{ 0, 4 },
            .north = .{ 0, 4 },
        }) },
        .mining_speed = 2,
        .breaking_tool = .axe,
    },
    .urple_leaves = .{
        .model_type = .{ .block = TextureIndexFromSide.initFill(.{ 2, 4 }) },
        .mining_speed = 0.3,
    },
    .urple_wood_plank = .{
        .model_type = .{ .block = TextureIndexFromSide.initFill(.{ 3, 4 }) },
        .mining_speed = 1.5,
    },
});

test {
    _ = Position;
}

fn genBlockPreviewMesh(alloc: std.mem.Allocator, mesh_size: @Vector(3, f32), block_type: Type) !rl.Mesh {
    // TODO: dont generate a whole block lmao
    // you only see three sides in the preview...

    const width, const height, const length = mesh_size;
    var mesh: rl.Mesh = .{};

    const vertices: []const f32 = &.{
        -width / 2, -height / 2, length / 2,
        width / 2,  -height / 2, length / 2,
        width / 2,  height / 2,  length / 2,
        -width / 2, height / 2,  length / 2,
        -width / 2, -height / 2, -length / 2,
        -width / 2, height / 2,  -length / 2,
        width / 2,  height / 2,  -length / 2,
        width / 2,  -height / 2, -length / 2,
        -width / 2, height / 2,  -length / 2,
        -width / 2, height / 2,  length / 2,
        width / 2,  height / 2,  length / 2,
        width / 2,  height / 2,  -length / 2,
        -width / 2, -height / 2, -length / 2,
        width / 2,  -height / 2, -length / 2,
        width / 2,  -height / 2, length / 2,
        -width / 2, -height / 2, length / 2,
        width / 2,  -height / 2, -length / 2,
        width / 2,  height / 2,  -length / 2,
        width / 2,  height / 2,  length / 2,
        width / 2,  -height / 2, length / 2,
        -width / 2, -height / 2, -length / 2,
        -width / 2, -height / 2, length / 2,
        -width / 2, height / 2,  length / 2,
        -width / 2, height / 2,  -length / 2,
    };

    const top_texcoords = texCoordsForSide(block_type, .{}, .top);
    const north_texcoords = texCoordsForSide(block_type, .{}, .north);
    const east_texcoords = texCoordsForSide(block_type, .{}, .east);

    const texcoords: []const f32 = &.{
        // back facing one
        0.0,                0.0,
        0.0,                0.0,
        0.0,                0.0,
        0.0,                0.0,
        // bottom left
        east_texcoords[6],  east_texcoords[7],
        east_texcoords[2],  east_texcoords[3],
        east_texcoords[0],  east_texcoords[1],
        east_texcoords[4],  east_texcoords[5],
        // top
        top_texcoords[0],   top_texcoords[1],
        top_texcoords[4],   top_texcoords[5],
        top_texcoords[6],   top_texcoords[7],
        top_texcoords[2],   top_texcoords[3],
        // back facing one
        0.0,                0.0,
        0.0,                0.0,
        0.0,                0.0,
        0.0,                0.0,
        // back facing one
        0.0,                0.0,
        0.0,                0.0,
        0.0,                0.0,
        0.0,                0.0,
        // bottom right
        north_texcoords[0], north_texcoords[1],
        north_texcoords[4], north_texcoords[5],
        north_texcoords[6], north_texcoords[7],
        north_texcoords[2], north_texcoords[3],
    };

    const normals: []const f32 = &.{ 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 0.0 };

    mesh.vertices = (try alloc.alloc(f32, 24 * 3)).ptr;
    @memcpy(mesh.vertices[0 .. 24 * 3], vertices);

    mesh.texcoords = (try alloc.alloc(f32, 24 * 2)).ptr;
    @memcpy(mesh.texcoords[0 .. 24 * 2], texcoords);

    mesh.normals = (try alloc.alloc(f32, 24 * 3)).ptr;
    @memcpy(mesh.normals[0 .. 24 * 3], normals);

    mesh.indices = (try alloc.alloc(c_ushort, 36)).ptr;

    var k: c_ushort = 0;

    // Indices can be initialized right now
    var i: u32 = 0;
    while (i < 36) : (i += 6) {
        mesh.indices[i] = 4 * k;
        mesh.indices[i + 1] = 4 * k + 1;
        mesh.indices[i + 2] = 4 * k + 2;
        mesh.indices[i + 3] = 4 * k;
        mesh.indices[i + 4] = 4 * k + 2;
        mesh.indices[i + 5] = 4 * k + 3;

        k += 1;
    }

    mesh.vertexCount = 24;
    mesh.triangleCount = 12;

    // Upload vertex data to GPU (static mesh)
    rl.UploadMesh(&mesh, false);

    return mesh;
}

fn unloadPreviewMesh(alloc: std.mem.Allocator, mesh: rl.Mesh) void {
    alloc.free(mesh.vertices[0 .. 24 * 3]);
    alloc.free(mesh.texcoords[0 .. 24 * 2]);
    alloc.free(mesh.normals[0 .. 24 * 3]);
    alloc.free(mesh.indices[0..36]);
}

pub fn texCoordsForSide(t: Type, rot: Rotation, global_side: Side) @Vector(8, f32) {
    // TODO: don't calculate this every time...
    const block_sprites_per_row: f32 = @floatFromInt(@divExact(Block.block_sprite_atlas.width, Block.block_sprite_size));
    const block_sprites_per_col: f32 = @floatFromInt(@divExact(Block.block_sprite_atlas.height, Block.block_sprite_size));

    const local_side = blk: {
        var global_dir = global_side.toVector();

        const wn_rad = @as(f32, @floatFromInt(rot.wn_rots)) * std.math.pi / 2.0;
        const nt_rad = @as(f32, @floatFromInt(rot.nt_rots)) * std.math.pi / 2.0;

        global_dir = rl.Vector3RotateByAxisAngle(global_dir, rl.Vector3{ .y = 1 }, wn_rad);
        global_dir = rl.Vector3RotateByAxisAngle(global_dir, rl.Vector3{ .x = 1 }, nt_rad);

        break :blk Side.fromVector(global_dir);
    };
    const tex_coord_idx = Block.block_info.get(t).model_type.block.get(local_side);

    const tex_coord_x = ztg.math.divf32(tex_coord_idx[0], block_sprites_per_row) catch unreachable;
    const tex_coord_y = ztg.math.divf32(tex_coord_idx[1], block_sprites_per_col) catch unreachable;

    // TODO: see if you can have the same tex coords for each side
    return switch (global_side) {
        .north => .{
            tex_coord_x,                             tex_coord_y + 1 / block_sprites_per_col,
            tex_coord_x,                             tex_coord_y,
            tex_coord_x + 1 / block_sprites_per_row, tex_coord_y + 1 / block_sprites_per_col,
            tex_coord_x + 1 / block_sprites_per_row, tex_coord_y,
        },
        .south => .{
            tex_coord_x,                             tex_coord_y,
            tex_coord_x + 1 / block_sprites_per_row, tex_coord_y,
            tex_coord_x,                             tex_coord_y + 1 / block_sprites_per_col,
            tex_coord_x + 1 / block_sprites_per_row, tex_coord_y + 1 / block_sprites_per_col,
        },
        .west => .{
            tex_coord_x + 1 / block_sprites_per_row, tex_coord_y,
            tex_coord_x + 1 / block_sprites_per_row, tex_coord_y + 1 / block_sprites_per_col,
            tex_coord_x,                             tex_coord_y,
            tex_coord_x,                             tex_coord_y + 1 / block_sprites_per_col,
        },
        .east => .{
            tex_coord_x,                             tex_coord_y,
            tex_coord_x + 1 / block_sprites_per_row, tex_coord_y,
            tex_coord_x,                             tex_coord_y + 1 / block_sprites_per_col,
            tex_coord_x + 1 / block_sprites_per_row, tex_coord_y + 1 / block_sprites_per_col,
        },
        .top, .bottom => .{
            tex_coord_x + 1 / block_sprites_per_row, tex_coord_y + 1 / block_sprites_per_col,
            tex_coord_x + 1 / block_sprites_per_row, tex_coord_y,
            tex_coord_x,                             tex_coord_y + 1 / block_sprites_per_col,
            tex_coord_x,                             tex_coord_y,
        },
    };
}

pub fn drawPreview(t: Type, rect: rl.Rectangle) void {
    const i: u32 = @intFromEnum(t);

    rl.DrawTexturePro(Block.snapshot_tex.texture, .{
        .x = @floatFromInt(i * snap_size),
        .y = 0,
        .width = snap_size,
        .height = snap_size,
    }, rect, .{}, 0, rl.WHITE);
}
