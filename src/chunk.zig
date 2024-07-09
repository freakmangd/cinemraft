const std = @import("std");
const ztg = @import("zentig");
const zrl = @import("zrl");
const zmath = @import("zmath");
const rl = zrl.rl;
const c = @import("init.zig");
const Block = c.Block;

const Chunk = @This();

pub const MeshData = @import("chunk_mesh.zig");
pub const BlockArray = c.Array3d(horizontal_size, 32, horizontal_size, Block);
pub const BlockModels = std.ArrayListUnmanaged(struct { Block.Index, rl.Model });

blocks: *BlockArray,

blocks_mesh: MeshData = .{ .alloc = undefined },
block_models: BlockModels = .{},
level_of_detail: u8 = 1,
mesh_needs_rebuilt: bool = false,

pub const to_world_space = horizontal_size * Block.size;
pub const horizontal_size = 16;

pub fn init(chunk: *Chunk, alloc: std.mem.Allocator) !void {
    const ba = try alloc.create(BlockArray);
    ba.* = BlockArray.filled(.{});
    chunk.* = .{ .blocks = ba };
}

pub fn deinit(self: *Chunk, alloc: std.mem.Allocator) void {
    for (self.blocks.items) |block| block.deinit(alloc);
    alloc.destroy(self.blocks);

    if (self.blocks_mesh.vao_id > 0) self.blocks_mesh.unload();
    self.block_models.deinit(alloc);
}

pub fn draw(self: Chunk, pos: Chunk.Position, block_mat: rl.Material) void {
    if (self.blocks_mesh.vao_id == 0) return;

    const transform = rl.MatrixTranslate(@floatFromInt(pos.x * Chunk.to_world_space), 0, @floatFromInt(pos.z * Chunk.to_world_space));
    self.blocks_mesh.draw(block_mat, transform);

    for (self.block_models.items) |idx_model| {
        const idx, const model = idx_model;
        rl.DrawModel(model, @bitCast(idx.toWorldV(pos) + @Vector(3, f32){ Block.size / 2, 0, Block.size / 2 }), 8, rl.WHITE);
    }
}

pub fn setLod(self: *Chunk, lod: u8) void {
    if (self.level_of_detail == lod) return;

    self.level_of_detail = lod;
    self.mesh_needs_rebuilt = true;
}

pub fn uploadMesh(chunk: *Chunk, alloc: std.mem.Allocator) !void {
    if (chunk.blocks_mesh.vao_id > 0) {
        chunk.blocks_mesh.unload();
        chunk.block_models.deinit(alloc);
    }

    try chunk.blocks_mesh.upload(false);
}

/// bare minimum of setting block in chunk
/// doesn't do any visibility/lighting calc, doesn't call onPlace
pub fn setBlock(
    self: *Chunk,
    block_index: Block.Index,
    block_type: Block.Type,
) *Block {
    const b = self.blocks.getPtr(block_index.x, block_index.y, block_index.z);
    b.* = .{ .type = block_type };
    return b;
}

pub const Key = u64;

pub const Position = packed struct(Key) {
    x: i32,
    z: i32,

    pub inline fn initKey(x: i32, z: i32) Key {
        return @bitCast(Position{ .x = x, .z = z });
    }

    pub inline fn eql(a: Position, b: Position) bool {
        return a.x == b.x and a.z == b.z;
    }

    pub inline fn toKey(self: Position) Key {
        return @bitCast(self);
    }

    pub inline fn fromKey(key: Key) Position {
        return @bitCast(key);
    }

    pub inline fn toWorld(self: Position) rl.Vector3 {
        return .{
            .x = @floatFromInt(self.x * Chunk.to_world_space),
            .z = @floatFromInt(self.z * Chunk.to_world_space),
        };
    }

    pub inline fn toWorldV(self: Position) @Vector(3, f32) {
        return .{
            @floatFromInt(self.x * Chunk.to_world_space),
            0,
            @floatFromInt(self.z * Chunk.to_world_space),
        };
    }

    pub inline fn toWorldZ(self: Position) ztg.Vec3 {
        return .{
            .x = @floatFromInt(self.x * Chunk.to_world_space),
            .z = @floatFromInt(self.z * Chunk.to_world_space),
        };
    }

    pub fn fromWorld(world_pos: rl.Vector3) Position {
        return .{
            .x = @intFromFloat(@floor(world_pos.x / Chunk.to_world_space)),
            .z = @intFromFloat(@floor(world_pos.z / Chunk.to_world_space)),
        };
    }

    pub fn containingBlockPos(pos: Block.Position) Position {
        const x_f: f64 = @floatFromInt(pos.x);
        const z_f: f64 = @floatFromInt(pos.z);

        return .{
            .x = @intFromFloat(@floor(x_f / Chunk.horizontal_size)),
            .z = @intFromFloat(@floor(z_f / Chunk.horizontal_size)),
        };
    }

    pub inline fn shift(self: Position, dir: Direction) Position {
        return switch (dir) {
            .north => .{ .x = self.x, .z = self.z + 1 },
            .south => .{ .x = self.x, .z = self.z - 1 },
            .east => .{ .x = self.x + 1, .z = self.z },
            .west => .{ .x = self.x - 1, .z = self.z },
        };
    }

    pub inline fn shiftInPlace(self: *Position, dir: Direction) void {
        return switch (dir) {
            .north => self.z += 1,
            .south => self.z -= 1,
            .east => self.x += 1,
            .west => self.x -= 1,
        };
    }

    pub fn format(value: Position, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("({}, {})", .{ value.x, value.z });
    }
};

pub const Direction = enum {
    north,
    south,
    west,
    east,
};

test "chunk key" {
    const pos_x: i32 = 10;
    const pos_z: i32 = -25;

    const key = Chunk.Position.toKey(.{ .x = pos_x, .z = pos_z });
    const result = Chunk.Position.fromKey(key);

    try std.testing.expectEqual(Chunk.Position{ .x = 10, .z = -25 }, result);
}
