const std = @import("std");
const builtin = @import("builtin");
const opts = @import("opts");
const ztg = @import("zentig");
const zrl = @import("zrl");
const rl = zrl.rl;
const c = @import("init.zig");
const chunk_gen = @import("chunk_generator.zig");
const Player = c.Player;
const Chunk = c.Chunk;
const BlockArray = Chunk.BlockArray;
const Block = c.Block;
const Side = Block.Side;

const ChunkManager = @This();

const LoadedChunks = std.AutoArrayHashMapUnmanaged(u64, Chunk);
const ToBePlaced = std.AutoHashMapUnmanaged(Chunk.Key, std.ArrayListUnmanaged(struct { Block.Index, Block.Type }));

alloc: std.mem.Allocator = undefined,
rand: std.Random = undefined,

seed: u32 = 8,
to_be_placed: ToBePlaced = .{},

loaded_chunks: LoadedChunks = .{},

generate_threads: std.Thread.Pool = undefined,
generating_chunks: std.AutoHashMapUnmanaged(Chunk.Key, *BlockArray) = .{},

finished_chunks: std.ArrayListUnmanaged(struct { pos: Chunk.Position, chunk: Chunk }) = .{},
finished_chunks_mutex: std.Thread.Mutex = .{},

pub fn include(comptime wb: *ztg.WorldBuilder) void {
    wb.addResource(ChunkManager, .{});
    wb.addSystems(.{
        .init = init,
        .draw = draw,
        .update = update,
        .deinit = deinit,
    });
}

pub fn init(cm: *ChunkManager, alloc: std.mem.Allocator, rand: std.Random) !void {
    cm.alloc = alloc;
    cm.rand = rand;
    try cm.generate_threads.init(.{ .allocator = alloc });
}

pub fn deinit(self: *ChunkManager) void {
    for (self.loaded_chunks.values()) |*chunk| {
        chunk.deinit(self.alloc);
    }
    self.loaded_chunks.deinit(self.alloc);

    var iter = self.to_be_placed.valueIterator();
    while (iter.next()) |to_be_placed| to_be_placed.deinit(self.alloc);
    self.to_be_placed.deinit(self.alloc);

    self.finished_chunks.deinit(self.alloc);
    self.generate_threads.deinit();

    var generating_iter = self.generating_chunks.valueIterator();
    while (generating_iter.next()) |blocks| {
        // destroy any orphaned block arrays
        self.alloc.destroy(blocks.*);
    }
    self.generating_chunks.deinit(self.alloc);
}

var load_dist_idx: usize = 1;
fn update(
    self: *ChunkManager,
    com: ztg.Commands,
    input: c.Input,
    player_q: ztg.Query(.{Player.Camera}),
) !void {
    blk: {
        self.finished_chunks_mutex.lock();
        defer self.finished_chunks_mutex.unlock();

        if (self.finished_chunks.items.len == 0) break :blk;
        const len = if (opts.timing) self.finished_chunks.items.len;

        const start = if (opts.timing) std.time.milliTimestamp();
        defer if (opts.timing) std.log.info("Put {} chunks in {}ms", .{ len, std.time.milliTimestamp() - start });

        for (self.finished_chunks.items) |*finished| {
            for (&finished.chunk.blocks.items, 0..) |*block, i| {
                const index = Block.Index.fromArrayIndex(i);
                try block.onPlace(com, self.alloc, index.toPosition(finished.pos), .{});

                if (block.type != .none)
                    self.calcExposedForBlockAndNeighbors(&finished.chunk, finished.pos, block, index);
            }

            finished.chunk.mesh_needs_rebuilt = true;
            try self.loaded_chunks.put(self.alloc, finished.pos.toKey(), finished.chunk);
        }

        self.finished_chunks.clearRetainingCapacity();
        self.generating_chunks.clearRetainingCapacity();
    }

    if (input.isPressed(0, .change_render_distance)) {
        load_dist_idx += 1;
        if (load_dist_idx == 5) load_dist_idx = 0;
    }

    for (player_q.items(0)) |pc| {
        const max_chunks_loaded = 999;
        const max_chunks_rebuilt = 999;

        const load_dist: u31 = switch (load_dist_idx) {
            0 => 5,
            1 => 10,
            2 => 15,
            3 => 25,
            4 => 35,
            else => unreachable,
        };

        const camera_chunk = Chunk.Position.fromWorld(pc.camera.position);

        var chunks_loaded: usize = 0;
        var chunks_rebuilt: usize = 0;

        if (self.loaded_chunks.getPtr(camera_chunk.toKey())) |chunk| {
            //chunk.setLod(1);
            if (chunk.mesh_needs_rebuilt) {
                chunks_rebuilt += 1;
                try chunk.generateMesh(self.alloc);
            }
        } else {
            try self.generateChunk(camera_chunk);
            chunks_loaded += 1;
        }

        outer: for (1..load_dist + 1) |_len| {
            const len: u31 = @intCast(_len);
            const run_len = len * 2;
            const lod: u8 = switch (len) {
                //0...24 => 1,
                //25...34 => 4,
                else => 1,
            };

            var chunk_pos = Chunk.Position{ .x = camera_chunk.x - len, .z = camera_chunk.z - len };
            for ([_]Chunk.Direction{ .east, .north, .west, .south }) |dir| {
                for (0..run_len) |_| {
                    chunk_pos.shiftInPlace(dir);

                    if (self.loaded_chunks.getPtr(chunk_pos.toKey())) |chunk| {
                        chunk.setLod(lod);
                        if (chunk.mesh_needs_rebuilt and chunks_rebuilt < max_chunks_rebuilt) {
                            chunks_rebuilt += 1;
                            try chunk.generateMesh(self.alloc);
                        }
                    } else {
                        try self.generateChunk(chunk_pos);
                        chunks_loaded += 1;
                        if (chunks_loaded > max_chunks_loaded) break :outer;
                    }
                }
            }
        }

        const max_remove_per_frame = 3;
        const chunk_x_min: i32 = (camera_chunk.x - load_dist) - 1;
        const chunk_x_max: i32 = (camera_chunk.x + load_dist) + 1;
        const chunk_z_min: i32 = (camera_chunk.z - load_dist) - 1;
        const chunk_z_max: i32 = (camera_chunk.z + load_dist) + 1;

        var to_remove: [max_remove_per_frame]u64 = undefined;
        var to_remove_len: usize = 0;

        for (self.loaded_chunks.keys()) |chunk_key| {
            const chunk_pos = Chunk.Position.fromKey(chunk_key);
            if (chunk_pos.x < chunk_x_min or chunk_pos.x > chunk_x_max or chunk_pos.z < chunk_z_min or chunk_pos.z > chunk_z_max) {
                to_remove[to_remove_len] = chunk_key;
                to_remove_len += 1;

                if (to_remove_len == max_remove_per_frame) break;
            }
        }

        for (to_remove[0..to_remove_len]) |chunk_key| {
            const chunk = self.loaded_chunks.getPtr(chunk_key).?;
            chunk.deinit(self.alloc);
            std.debug.assert(self.loaded_chunks.swapRemove(chunk_key));
        }
    }
}

fn draw(cm: ChunkManager) !void {
    for (cm.loaded_chunks.values(), cm.loaded_chunks.keys()) |chunk, chunk_key| {
        const chunk_pos = Chunk.Position.fromKey(chunk_key);
        chunk.draw(chunk_pos, Block.material);
    }
}

pub fn generateChunk(self: *ChunkManager, chunk_pos: Chunk.Position) !void {
    const chunk_key = chunk_pos.toKey();
    const gop = try self.generating_chunks.getOrPut(self.alloc, chunk_key);
    errdefer _ = self.generating_chunks.remove(chunk_key);

    if (!gop.found_existing) {
        std.log.info("queuing chunk {} for generation...", .{chunk_pos});

        const block_arr = try self.alloc.create(BlockArray);
        block_arr.* = BlockArray.filled(.{});

        gop.value_ptr.* = block_arr;

        try self.generate_threads.spawn(generateChunkFn, .{ self, chunk_pos, block_arr });
    }
}

fn generateChunkFn(self: *ChunkManager, chunk_pos: Chunk.Position, block_arr: *BlockArray) void {
    var chunk: Chunk = .{ .blocks = block_arr };

    chunk_gen.generate(self.seed, &chunk, chunk_pos, 1) catch |err| {
        std.log.err("thread(chunk_gen): failed to generate chunk {}. Error: {}", .{ chunk_pos, err });
        return;
    };

    self.finished_chunks_mutex.lock();
    defer self.finished_chunks_mutex.unlock();

    self.finished_chunks.append(self.alloc, .{
        .chunk = chunk,
        .pos = chunk_pos,
    }) catch |err| {
        std.log.err("thread(chunk_gen): failed to append chunk {}. Error: {}", .{ chunk_pos, err });
        return;
    };
}

pub fn generateChunkBlocking(self: *ChunkManager, com: ztg.Commands, chunk_pos: Chunk.Position) !LoadedChunks.GetOrPutResult {
    const chunk_key = chunk_pos.toKey();
    const gop = try self.loaded_chunks.getOrPut(self.alloc, chunk_key);

    if (!gop.found_existing) {
        const chunk = gop.value_ptr;
        try Chunk.init(chunk, self.alloc);
        try chunk_gen.generate(com, self, chunk, chunk_pos, 1);

        if (self.to_be_placed.getPtr(chunk_key)) |to_be_placed| {
            for (to_be_placed.items) |index_type| {
                const block = try chunk.setBlock(index_type[0], index_type[1], .{});
                block.onPlace(com, self.alloc, index_type[0].toPosition(chunk_pos), .{});
                self.calcExposedForBlockAndNeighbors(chunk, chunk_pos, block, index_type[0]);
            }
            to_be_placed.deinit(self.alloc);
            _ = self.to_be_placed.remove(chunk_pos.toKey());
        }
    }

    return gop;
}

pub const HoveredBlockHit = struct {
    position: Block.Position,
    ray_collision: rl.RayCollision,
    block: Block = undefined,
};

pub fn hoveredBlock(chunks: *ChunkManager, camera: rl.Camera) ?HoveredBlockHit {
    const max_reach = (Block.size * 6) / 2;

    const mouse_ray = rl.GetMouseRay(.{
        .x = @floatFromInt(@divFloor(rl.GetScreenWidth(), 2)),
        .y = @floatFromInt(@divFloor(rl.GetScreenHeight(), 2)),
    }, camera);

    var closest_hit: ?HoveredBlockHit = null;
    var closest_hit_distance: f32 = std.math.floatMax(f32);

    const forward = rl.Vector3Scale(rl.Vector3Normalize(rl.Vector3Subtract(camera.target, camera.position)), max_reach);
    const check_center = zrl.rl.Vector3Add(camera.position, forward);

    const min_x_check: i64 = @intFromFloat((check_center.x - max_reach) / Block.size);
    const max_x_check: i64 = @intFromFloat((check_center.x + max_reach) / Block.size);
    const min_y_check: usize = @intFromFloat(@max(0, (check_center.y - max_reach) / Block.size));
    const max_y_check: usize = @intFromFloat(@max(0, (check_center.y + max_reach) / Block.size));
    const min_z_check: i64 = @intFromFloat((check_center.z - max_reach) / Block.size);
    const max_z_check: i64 = @intFromFloat((check_center.z + max_reach) / Block.size);

    var x: i64 = min_x_check;
    while (x < max_x_check) : (x += 1) {
        var y: usize = min_y_check;
        while (y < max_y_check) : (y += 1) {
            var z: i64 = min_z_check;
            while (z < max_z_check) : (z += 1) {
                const block_pos = Block.Position.init(x, y, z);
                if (block_pos.y >= Chunk.BlockArray.y_len) continue;

                const chunk_pos = Chunk.Position.containingBlockPos(block_pos);
                const chunk: *Chunk = chunks.loaded_chunks.getPtr(chunk_pos.toKey()) orelse continue;
                const block_idx = block_pos.toIndex();

                if (chunk.blocks.get(block_idx.x, block_idx.y, block_idx.z).type == .none) continue;

                const ray_collision = rl.GetRayCollisionBox(mouse_ray, .{
                    .min = block_pos.toWorld(),
                    .max = rl.Vector3Add(block_pos.toWorld(), zrl.vec3splat(Block.size)),
                });

                if (ray_collision.hit and ray_collision.distance < closest_hit_distance) {
                    closest_hit = .{
                        .position = block_pos,
                        .ray_collision = ray_collision,
                    };

                    closest_hit_distance = ray_collision.distance;
                }
            }
        }
    }

    if (closest_hit) |*ch| {
        const block_index = ch.position.toIndex();
        ch.block = chunks.loaded_chunks.getPtr(ch.position.toChunkPos().toKey()).?.blocks.get(block_index.x, block_index.y, block_index.z);
        return ch.*;
    }

    return null;
}

pub fn calcExposedForBlockAndNeighbors(self: *ChunkManager, chunk: *Chunk, chunk_pos: Chunk.Position, block: *Block, block_idx: Block.Index) void {
    const model_type = block.type.get(.model_type);

    for (std.enums.values(Side)) |side| {
        if (side == .top and block_idx.y == ChunkManager.BlockArray.y_len - 1) {
            block.exposed.set(Block.Side.top.int());
        } else if (self.getBlockAtOffset(chunk, chunk_pos, block_idx, side)) |chunk_block| {
            const n_chunk, const n_block = chunk_block;
            if (model_type == .block) {
                n_chunk.mesh_needs_rebuilt = true;
                n_block.exposed.setValue(side.opposite().int(), block.type == .none);
            }
            block.exposed.setValue(side.int(), n_block.type == .none or n_block.type.get(.model_type) == .model);
        }
    }
}

pub fn getBlockAtBlockPos(self: ChunkManager, block_pos: Block.Position) ?Block {
    if (block_pos.y > Chunk.BlockArray.y_len - 1) return null;

    const chunk_pos = Chunk.Position.containingBlockPos(block_pos);
    const block_idx = block_pos.toIndex();

    return (self.loaded_chunks.getPtr(chunk_pos.toKey()) orelse return null).blocks.get(block_idx.x, block_idx.y, block_idx.z);
}

pub fn getBlockAtOffset(
    self: *ChunkManager,
    this_chunk: *Chunk,
    chunk_pos: Chunk.Position,
    block_idx: Block.Index,
    offset_side: Side,
) ?struct { *Chunk, *Block } {
    switch (offset_side) {
        .top => {
            if (block_idx.y == BlockArray.y_len - 1) return null;
            return .{ this_chunk, this_chunk.blocks.getPtr(block_idx.x, block_idx.y + 1, block_idx.z) };
        },
        .bottom => {
            if (block_idx.y == 0) return null;
            return .{ this_chunk, this_chunk.blocks.getPtr(block_idx.x, block_idx.y - 1, block_idx.z) };
        },
        .east => {
            if (block_idx.x == BlockArray.x_len - 1) {
                var chunk = self.loaded_chunks.getPtr(chunk_pos.shift(.east).toKey()) orelse return null;
                return .{ chunk, chunk.blocks.getPtr(0, block_idx.y, block_idx.z) };
            }
            return .{ this_chunk, this_chunk.blocks.getPtr(block_idx.x + 1, block_idx.y, block_idx.z) };
        },
        .west => {
            if (block_idx.x == 0) {
                var chunk = self.loaded_chunks.getPtr(chunk_pos.shift(.west).toKey()) orelse return null;
                return .{ chunk, chunk.blocks.getPtr(BlockArray.x_len - 1, block_idx.y, block_idx.z) };
            }
            return .{ this_chunk, this_chunk.blocks.getPtr(block_idx.x - 1, block_idx.y, block_idx.z) };
        },
        .north => {
            if (block_idx.z == BlockArray.z_len - 1) {
                var chunk = self.loaded_chunks.getPtr(chunk_pos.shift(.north).toKey()) orelse return null;
                return .{ chunk, chunk.blocks.getPtr(block_idx.x, block_idx.y, 0) };
            }
            return .{ this_chunk, this_chunk.blocks.getPtr(block_idx.x, block_idx.y, block_idx.z + 1) };
        },
        .south => {
            if (block_idx.z == 0) {
                var chunk = self.loaded_chunks.getPtr(chunk_pos.shift(.south).toKey()) orelse return null;
                return .{ chunk, chunk.blocks.getPtr(block_idx.x, block_idx.y, BlockArray.z_len - 1) };
            }
            return .{ this_chunk, this_chunk.blocks.getPtr(block_idx.x, block_idx.y, block_idx.z - 1) };
        },
    }
}

pub const PlaceOpts = struct {
    placed_on: ?struct {
        block: Block,
        side: Block.Side,
    } = null,
    placer_pos: ?ztg.Vec3 = null,
    /// if `true` and `block_type` != .none,
    /// we don't check if theres already a block there
    ignore_previous: bool = false,
};

pub fn placeBlockInWorld(
    self: *ChunkManager,
    com: ztg.Commands,
    block_pos: Block.Position,
    block_type: Block.Type,
    place_opts: PlaceOpts,
) !bool {
    const block_idx = block_pos.toIndex();
    const chunk_pos = block_pos.toChunkPos();
    const chunk_key = chunk_pos.toKey();

    if (self.loaded_chunks.getPtr(chunk_key)) |chunk| {
        const b = try self.placeBlockInLoadedChunk(com, chunk, chunk_pos, block_idx, block_type, place_opts);
        return b != null;
    } else {
        if (block_pos.y > BlockArray.y_len - 1) return false;

        const gop = try self.to_be_placed.getOrPut(self.alloc, chunk_key);

        if (!gop.found_existing) gop.value_ptr.* = .{};
        try gop.value_ptr.append(self.alloc, .{ block_idx, block_type });
        return true;
    }
}

/// placeBlockInWorld except you already have the chunk pointer... so give it!!!
pub fn placeBlockInLoadedChunk(
    self: *ChunkManager,
    com: ztg.Commands,
    chunk: *Chunk,
    chunk_pos: Chunk.Position,
    block_idx: Block.Index,
    block_type: Block.Type,
    place_opts: PlaceOpts,
) !?*Block {
    if (block_idx.y >= Chunk.BlockArray.y_len) return null;

    if (block_type == .none) {
        const block = chunk.blocks.getPtr(block_idx.x, block_idx.y, block_idx.z);
        if (block.type == .none) return block;

        try block.onBreak(block_idx.toPosition(chunk_pos), self.alloc, self.rand, com);
        block.* = .{};

        self.calcExposedForBlockAndNeighbors(chunk, chunk_pos, block, block_idx);
        chunk.mesh_needs_rebuilt = true;

        return block;
    } else if (place_opts.ignore_previous or chunk.blocks.getPtr(block_idx.x, block_idx.y, block_idx.z).type == .none) {
        const block = chunk.setBlock(block_idx, block_type);
        try block.onPlace(com, self.alloc, block_idx.toPosition(chunk_pos), place_opts);

        self.calcExposedForBlockAndNeighbors(chunk, chunk_pos, block, block_idx);
        chunk.mesh_needs_rebuilt = true;

        return block;
    }

    return null;
}

// OLD
fn placeBlockFromOffset(
    self: *ChunkManager,
    _chunk_pos: Chunk.Position,
    _block_idx: Block.Index,
    block_type: Block.Type,
    _offset_x: i32,
    offset_y: i32,
    _offset_z: i32,
) !void {
    var chunk_pos = _chunk_pos;
    var block_idx = _block_idx;
    var offset_x = _offset_x;
    var offset_z = _offset_z;

    if (block_idx.y == 0 and offset_y < 0) {
        std.log.warn("Tried to add a block below the world at {} 0 {}", .{ block_idx.x, block_idx.z });
        return;
    } else if (block_idx.y == BlockArray.y_len - 1 and offset_y > 0) {
        std.log.warn("Tried to add a block above the world at {} 0 {}", .{ block_idx.x, block_idx.z });
        return;
    }

    if (block_idx.x == 0 and _offset_x < 0) {
        chunk_pos.x -= 1;
        block_idx.x = Chunk.horizontal_size;
    } else if (block_idx.x == BlockArray.x_len - 1 and _offset_x > 0) {
        chunk_pos.x += 1;
        block_idx.x = 0;
        offset_x = 0;
    }

    if (block_idx.z == 0 and _offset_z < 0) {
        chunk_pos.z -= 1;
        block_idx.z = Chunk.horizontal_size;
    } else if (block_idx.z == BlockArray.z_len - 1 and _offset_z > 0) {
        chunk_pos.z += 1;
        block_idx.z = 0;
        offset_z = 0;
    }

    //std.log.info("trying to place block at chunk (key: {}, x: {}, z: {}) at ({}, {}, {})...", .{
    //    chunk_pos.toKey(),
    //    chunk_pos.x,
    //    chunk_pos.z,
    //    @as(usize, @intCast(@as(i32, @intCast(block_idx.x)) + offset_x)),
    //    @as(usize, @intCast(@as(i32, @intCast(block_idx.y)) + offset_y)),
    //    @as(usize, @intCast(@as(i32, @intCast(block_idx.z)) + offset_z)),
    //});

    const place_x: usize = @intCast(block_idx.x + offset_x);
    const place_y: usize = @intCast(block_idx.y + offset_y);
    const place_z: usize = @intCast(block_idx.z + offset_z);
    try self.placeBlockInChunk(chunk_pos, Block.Index.fromUsize(place_x, place_y, place_z), block_type, false);
}
