const std = @import("std");
const ztg = @import("zentig");
const znoise = @import("znoise");
const c = @import("init.zig");
const opts = @import("opts");
const Block = c.Block;
const Chunk = c.Chunk;
const ChunkManager = c.ChunkManager;

const base_terrain_height = 20;
const max_terrain_height_diff = 5;

const dirt_depth = 2;

fn setExposedForChunkColumn(chunk: *Chunk, x: u8, z: u8, start_y: usize, exposed_side: Block.Side) void {
    for (start_y..Chunk.BlockArray.y_len) |block_y| {
        chunk.blocks.getPtr(x, block_y, z).exposed.set(exposed_side.int());
    }
}

pub fn generate(
    seed: u32,
    chunk: *Chunk,
    chunk_position: Chunk.Position,
    lod: u8,
) !void {
    const start = if (opts.timing) std.time.milliTimestamp();
    defer if (opts.timing) std.log.info("Generated chunk in {}ms", .{std.time.milliTimestamp() - start});

    if (false) {
        var rng = std.rand.DefaultPrng.init(0);
        const rand = rng.random();

        for (0..Chunk.BlockArray.items_len) |i| {
            const x, const y, const z = Chunk.BlockArray.position(i);
            _ = try placeBlockInLoadedChunk(chunk, Block.Index.init(x, y, z), rand.enumValue(Block.Type), .{ .ignore_previous = true });
        }

        return;
    }

    //const north = cm.loaded_chunks.getPtr(chunk_position.shift(.north).toKey());
    //const south = cm.loaded_chunks.getPtr(chunk_position.shift(.south).toKey());
    //const east = cm.loaded_chunks.getPtr(chunk_position.shift(.east).toKey());
    //const west = cm.loaded_chunks.getPtr(chunk_position.shift(.west).toKey());

    const gen = znoise.FnlGenerator{
        .seed = @bitCast(seed),
        .noise_type = .perlin,
    };

    {
        var block_rng = std.Random.DefaultPrng.init(0);
        const block_rand = block_rng.random();

        var block_x: u8 = 0;
        while (block_x < Chunk.horizontal_size) : (block_x += 1) {
            var block_z: u8 = 0;
            while (block_z < Chunk.horizontal_size) : (block_z += 1) {
                const block_gx = chunk_position.x * Chunk.horizontal_size + block_x;
                const block_gz = chunk_position.z * Chunk.horizontal_size + block_z;
                const block_gxf: f32 = @floatFromInt(block_gx);
                const block_gzf: f32 = @floatFromInt(block_gz);

                const top_32_bits: u32 = @bitCast(block_gx);
                const bottom_32_bits: u32 = @bitCast(block_gz);
                block_rng.seed(
                    @as(u64, bottom_32_bits) | (@as(u64, top_32_bits) << 32),
                );

                const relative_height_noise = gen.noise2(block_gxf * 6, block_gzf * 6) * 0.5 + 0.5;
                const rel_height: u32 = @intFromFloat(relative_height_noise * max_terrain_height_diff);
                const block_max_y: usize = @intCast(base_terrain_height + rel_height + 1);

                {
                    const block_idx = Block.Index.init(block_x, 0, block_z);
                    _ = chunk.setBlock(block_idx, .bedrock);
                }

                for (1..block_max_y - dirt_depth) |block_y| {
                    const block_idx = Block.Index.init(block_x, block_y, block_z);
                    _ = chunk.setBlock(block_idx, .stone);
                }

                for (block_max_y - dirt_depth..block_max_y - 1) |block_y| {
                    const block_idx = Block.Index.init(block_x, block_y, block_z);
                    _ = chunk.setBlock(block_idx, .dirt);
                }

                {
                    const block_idx = Block.Index.init(block_x, block_max_y - 1, block_z);
                    _ = chunk.setBlock(block_idx, .grass);
                }

                var start_none_y: usize = base_terrain_height + rel_height + 1;

                if (block_rand.float(f32) < 0.001) {
                    const block_index = Block.Index.init(block_x, block_max_y, block_z);

                    const tree_types = [_]TreeOpts{
                        .{ .wood = .wood, .leaves = .leaves },
                        .{ .wood = .urple_wood, .leaves = .urple_leaves },
                    };

                    const height = try generateTree(
                        block_rand,
                        chunk,
                        chunk_position,
                        block_index,
                        tree_types[block_rand.uintLessThan(usize, tree_types.len)],
                    );
                    start_none_y += height;
                }

                if (start_none_y >= Chunk.BlockArray.y_len - 1) continue;

                //if (block_x == 0) {
                //    if (west) |w| {
                //        setExposedForChunkColumn(w, Chunk.BlockArray.x_len - 1, block_z, start_none_y, .east);
                //    }
                //} else if (block_x == Chunk.BlockArray.x_len - 1) {
                //    if (east) |e| {
                //        setExposedForChunkColumn(e, 0, block_z, start_none_y, .west);
                //    }
                //}

                //if (block_z == 0) {
                //    if (south) |s| {
                //        setExposedForChunkColumn(s, block_x, Chunk.BlockArray.z_len - 1, start_none_y, .north);
                //    }
                //} else if (block_z == Chunk.BlockArray.z_len - 1) {
                //    if (north) |n| {
                //        setExposedForChunkColumn(n, block_x, 0, start_none_y, .south);
                //    }
                //}
            }
        }
    }

    chunk.setLod(lod);
    //if (north) |n| n.mesh_needs_rebuilt = true;
    //if (south) |n| n.mesh_needs_rebuilt = true;
    //if (west) |n| n.mesh_needs_rebuilt = true;
    //if (east) |n| n.mesh_needs_rebuilt = true;
}

const TreeOpts = struct {
    wood: Block.Type,
    leaves: Block.Type,
};

pub fn generateTree(
    rand: std.Random,
    chunk: *Chunk,
    chunk_pos: Chunk.Position,
    block_index: Block.Index,
    tree_opts: TreeOpts,
) !u8 {
    _ = rand;
    _ = chunk;
    _ = chunk_pos;
    _ = block_index;
    _ = tree_opts;

    return 0;
    //const height = rand.intRangeAtMost(u8, 5, 8);
    //const leaves_height = rand.intRangeAtMost(u8, 4, 5);

    //for (0..height) |y| {
    //    _ = chunk.setBlock(Block.Index.init(
    //        block_index.x,
    //        block_index.y + y,
    //        block_index.z,
    //    ), tree_opts.wood);
    //}

    //{
    //    const center_idx = block_index.shift(.top, height);
    //    const center_pos = center_idx.toPosition(chunk_pos);
    //    _ = chunk.setBlock(center_idx, tree_opts.leaves);

    //    for (Block.Side.no_top_bottom) |side| {
    //        const new_chunk_pos = center_pos.shift(side, 1);
    //        _ = try placeBlockInWorld(new_chunk_pos, tree_opts.leaves, .{});
    //    }
    //}

    //var block_y: u8 = height - 1;
    //while (block_y > height - leaves_height) : (block_y -= 1) {
    //    const center_pos = block_index.shift(.top, block_y).toPosition(chunk_pos);

    //    var shift_x: i32 = -2;
    //    while (shift_x <= 2) : (shift_x += 1) {
    //        var shift_z: i32 = -2;
    //        while (shift_z <= 2) : (shift_z += 1) {
    //            const new_chunk_pos = center_pos.shiftV(.{ shift_x, 0, shift_z });
    //            _ = try placeBlockInWorld(cm, new_chunk_pos, tree_opts.leaves, .{});
    //        }
    //    }
    //}

    //return height;
}

// we have our own version of these functions because of multithreading.
// we dont do any allocating or interacting with the world while generating.
// once we generate everything, we go back onto the main thread for onPlace
// calls which does stuff like allocate/generate loot for chests

pub fn placeBlockInWorld(
    cm: *ChunkManager,
    block_pos: Block.Position,
    block_type: Block.Type,
    place_opts: ChunkManager.PlaceOpts,
) !bool {
    const block_idx = block_pos.toIndex();
    const chunk_pos = block_pos.toChunkPos();
    const chunk_key = chunk_pos.toKey();

    if (cm.loaded_chunks.getPtr(chunk_key)) |chunk| {
        const b = placeBlockInLoadedChunk(chunk, block_idx, block_type, place_opts);
        return b != null;
    } else {
        if (block_pos.y > c.Chunk.BlockArray.y_len - 1) return false;

        const gop = try cm.to_be_placed.getOrPut(cm.alloc, chunk_key);

        if (!gop.found_existing) gop.value_ptr.* = .{};
        try gop.value_ptr.append(cm.alloc, .{ block_idx, block_type });
        return true;
    }
}

pub fn placeBlockInLoadedChunk(
    chunk: *Chunk,
    block_idx: Block.Index,
    block_type: Block.Type,
    place_opts: ChunkManager.PlaceOpts,
) ?*Block {
    if (block_idx.y >= Chunk.BlockArray.y_len) return null;
    std.debug.assert(block_type != .none);

    if (place_opts.ignore_previous or chunk.blocks.getPtr(block_idx.x, block_idx.y, block_idx.z).type == .none) {
        return chunk.setBlock(block_idx, block_type);
    }

    return null;
}
