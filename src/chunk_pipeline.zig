const std = @import("std");
const ztg = @import("zentig");
const zrl = @import("zrl");
const rl = zrl.rl;
const c = @import("init.zig");
const chunk_gen = @import("chunk_generator.zig");
const Block = c.Block;
const Chunk = c.Chunk;
const BlockArray = Chunk.BlockArray;

const Pipeline = @This();

cm: *c.ChunkManager,

alloc: std.mem.Allocator,
thread_alloc: std.heap.ThreadSafeAllocator,

thread_pool: std.Thread.Pool,

queue: std.AutoHashMapUnmanaged(Chunk.Key, Step) = .{},
queue_mutex: std.Thread.Mutex = .{},

pub fn init(self: *Pipeline, cm: *c.ChunkManager) !void {
    self.cm = cm;
    self.alloc = cm.alloc;
    self.thread_alloc = .{ .child_allocator = cm.alloc };
    try self.thread_pool.init(.{ .allocator = cm.alloc });
}

pub fn deinit(self: *Pipeline) void {
    self.thread_pool.deinit();

    var iter = self.queue.valueIterator();
    while (iter.next()) |step| {
        step.cancel(self.alloc);
    }
    self.queue.deinit(self.alloc);
}

pub fn update(self: *Pipeline, _: ztg.Commands) !void {
    self.queue_mutex.lock();
    defer self.queue_mutex.unlock();

    var iter = self.queue.valueIterator();
    var i: usize = 0;
    while (iter.next()) |step| : (i += 1) switch (step.type) {
        inline else => |s, tag| switch (step.state) {
            .running => {
                _ = tag;
            },
            .idle => {
                //std.log.info("{} starting chunk step {s}", .{ step.pos, @tagName(tag) });
                try s.run(self, step.*, &self.thread_pool);
                step.state = .running;
            },
            .finished => {
                //std.log.info("{} finishing chunk step {s}", .{ step.pos, @tagName(tag) });
                try s.finish(self, step.*);
                break;
            },
        },
    };
}

pub fn draw(self: *Pipeline) void {
    self.queue_mutex.lock();
    defer self.queue_mutex.unlock();

    var iter = self.queue.valueIterator();
    var i: usize = 0;
    while (iter.next()) |step| : (i += 1) {
        var buf: [128]u8 = undefined;
        const str = std.fmt.bufPrintZ(&buf, "{} -> {}", .{ step.pos, step.state }) catch "?";
        rl.DrawText(str, 0, @intCast(20 * i), 20, rl.WHITE);
    }
}

pub fn newChunk(pl: *Pipeline, pos: Chunk.Position, seed: u32) !void {
    pl.queue_mutex.lock();
    defer pl.queue_mutex.unlock();

    const gop = try pl.queue.getOrPut(pl.alloc, pos.toKey());

    if (!gop.found_existing) {
        const ba = try pl.alloc.create(Chunk.BlockArray);
        errdefer pl.alloc.destroy(ba);

        ba.* = Chunk.BlockArray.filled(.{});

        gop.value_ptr.* = .{
            .pos = pos,
            .type = .{ .place_blocks = .{
                .seed = seed,
                .block_arr = ba,
            } },
        };
    }
}

pub fn regenChunkMesh(pl: *Pipeline, pos: Chunk.Position, chunk: *Chunk) !void {
    pl.queue_mutex.lock();
    defer pl.queue_mutex.unlock();

    const gop = try pl.queue.getOrPut(pl.alloc, pos.toKey());

    if (!gop.found_existing) {
        try pl.regenChunkMeshInner(gop.value_ptr, pos, chunk);
    }
}

fn regenChunkMeshInner(pl: *Pipeline, step: *Step, pos: Chunk.Position, chunk: *Chunk) !void {
    chunk.mesh_needs_rebuilt = false;

    const blocks = try pl.alloc.create(Chunk.BlockArray);
    errdefer pl.alloc.destroy(blocks);
    blocks.* = chunk.blocks.*;

    const neighbors = try pl.alloc.create(Type.GenerateMesh.Neighbors);
    errdefer pl.alloc.destroy(neighbors);

    if (pl.cm.loaded_chunks.getPtr(pos.shift(.north).toKey())) |north_n| {
        neighbors.north = .{ .items = north_n.blocks.xySliceFull(0).* };
    }
    if (pl.cm.loaded_chunks.getPtr(pos.shift(.south).toKey())) |south_n| {
        neighbors.south = .{ .items = south_n.blocks.xySliceFull(BlockArray.z_len - 1).* };
    }
    if (pl.cm.loaded_chunks.getPtr(pos.shift(.east).toKey())) |east_n| {
        neighbors.east = @as(Type.GenerateMesh.Neighbors.EwArray, undefined);
        const east = &neighbors.east.?;

        var z: usize = 0;
        while (z < Type.GenerateMesh.Neighbors.EwArray.x_len) : (z += 1) {
            var y: usize = 0;
            while (y < Type.GenerateMesh.Neighbors.EwArray.y_len) : (y += 1) {
                east.set(z, y, east_n.blocks.get(0, y, z));
            }
        }
    }
    if (pl.cm.loaded_chunks.getPtr(pos.shift(.west).toKey())) |west_n| {
        neighbors.west = @as(Type.GenerateMesh.Neighbors.EwArray, undefined);
        const west = &neighbors.west.?;

        var z: usize = 0;
        while (z < Type.GenerateMesh.Neighbors.EwArray.x_len) : (z += 1) {
            var y: usize = 0;
            while (y < Type.GenerateMesh.Neighbors.EwArray.y_len) : (y += 1) {
                west.set(z, y, west_n.blocks.get(BlockArray.x_len - 1, y, z));
            }
        }
    }

    step.* = .{
        .pos = pos,
        .type = .{ .generate_mesh = .{
            .block_arr = blocks,
            .neighbors = neighbors,
        } },
    };
}

pub fn removeChunk(pl: *Pipeline, key: Chunk.Key, chunk: *Chunk) void {
    pl.queue_mutex.lock();
    defer pl.queue_mutex.unlock();

    blk: {
        const step = pl.queue.getPtr(key) orelse break :blk;
        if (step.state == .idle) {
            step.cancel(pl.alloc);
            _ = pl.queue.remove(key);
            break :blk;
        }
        return;
    }

    chunk.deinit(pl.cm.alloc);
    std.debug.assert(pl.cm.loaded_chunks.swapRemove(key));
}

const Step = struct {
    state: State = .idle,
    type: Type,
    pos: Chunk.Position,

    const State = enum {
        idle,
        running,
        finished,
    };

    pub fn cancel(self: *Step, alloc: std.mem.Allocator) void {
        switch (self.type) {
            inline else => |*s| s.cancel(alloc),
        }
    }
};

const Type = union(enum) {
    place_blocks: PlaceBlocks,
    generate_mesh: GenerateMesh,

    const PlaceBlocks = struct {
        seed: u32,
        block_arr: *Chunk.BlockArray,

        pub fn run(self: @This(), parent: *Pipeline, step: Step, thread_pool: *std.Thread.Pool) !void {
            try thread_pool.spawn(thread, .{ self.seed, self.block_arr, parent, step.pos });
        }

        fn thread(seed: u32, block_arr: *BlockArray, parent: *Pipeline, pos: Chunk.Position) void {
            var chunk: Chunk = .{ .blocks = block_arr };

            chunk_gen.generate(seed, &chunk, pos, 1) catch |err| {
                std.log.err("thread(chunk_gen): failed to generate chunk {}. Error: {}", .{ pos, err });
                return;
            };

            parent.queue_mutex.lock();
            defer parent.queue_mutex.unlock();

            const step_ptr = parent.queue.getPtr(pos.toKey()) orelse unreachable;
            step_ptr.state = .finished;
        }

        pub fn finish(self: @This(), parent: *Pipeline, step: Step) !void {
            const gop = try parent.cm.loaded_chunks.getOrPut(parent.cm.alloc, step.pos.toKey());
            gop.value_ptr.* = .{ .blocks = self.block_arr };

            try parent.regenChunkMeshInner(parent.queue.getPtr(step.pos.toKey()).?, step.pos, gop.value_ptr);
        }

        pub fn cancel(self: @This(), alloc: std.mem.Allocator) void {
            alloc.destroy(self.block_arr);
        }
    };

    const GenerateMesh = struct {
        block_arr: *Chunk.BlockArray,

        blocks_mesh: Chunk.MeshData = .{ .alloc = undefined },
        block_models: Chunk.BlockModels = .{},

        neighbors: *Neighbors,

        const Neighbors = struct {
            north: ?EwArray,
            south: ?EwArray,
            east: ?EwArray,
            west: ?EwArray,

            const EwArray = c.Array2d(BlockArray.z_len, BlockArray.y_len, Block);
        };

        pub fn run(self: @This(), parent: *Pipeline, step: Step, thread_pool: *std.Thread.Pool) !void {
            try thread_pool.spawn(thread, .{ self, parent, step.pos });
        }

        fn thread(self: @This(), parent: *Pipeline, pos: Chunk.Position) void {
            threadInner(self.block_arr, self.neighbors, parent, pos) catch |err| {
                std.log.err("Failed to generate mesh for {}. Error: {}", .{ pos, err });
            };
        }

        fn threadInner(block_arr: *BlockArray, neighbors: *Neighbors, parent: *Pipeline, pos: Chunk.Position) !void {
            //defer setFinished(step, parent, self.pos);

            for (&block_arr.items, 0..) |*block, i| {
                if (block.type == .none) continue;

                const x, const y, const z = BlockArray.position(i);
                var neighbor_blocks = std.EnumMap(Block.Side, Block.Type){};

                if (x == 0) blk: {
                    const west_block = (neighbors.west orelse break :blk).get(z, y);
                    neighbor_blocks.put(.west, west_block.type);
                } else {
                    neighbor_blocks.put(.west, block_arr.get(x - 1, y, z).type);
                }

                if (x == BlockArray.x_len - 1) blk: {
                    const east_block = (neighbors.west orelse break :blk).get(z, y);
                    neighbor_blocks.put(.east, east_block.type);
                } else {
                    neighbor_blocks.put(.east, block_arr.get(x + 1, y, z).type);
                }

                if (z == 0) blk: {
                    const south_block: Block = (neighbors.south orelse break :blk).get(x, y);
                    neighbor_blocks.put(.south, south_block.type);
                } else {
                    neighbor_blocks.put(.south, block_arr.get(x, y, z - 1).type);
                }

                if (z == BlockArray.z_len - 1) blk: {
                    const north_block: Block = (neighbors.north orelse break :blk).get(x, y);
                    neighbor_blocks.put(.north, north_block.type);
                } else {
                    neighbor_blocks.put(.north, block_arr.get(x, y, z + 1).type);
                }

                if (y != 0) {
                    neighbor_blocks.put(.bottom, block_arr.get(x, y - 1, z).type);
                }

                if (y != BlockArray.y_len - 1) {
                    neighbor_blocks.put(.top, block_arr.get(x, y + 1, z).type);
                }

                calcExposedForBlock(block, neighbor_blocks);
            }

            var blocks_mesh: Chunk.MeshData = .{ .alloc = parent.thread_alloc.allocator() };
            errdefer blocks_mesh.deinit();

            var block_models: Chunk.BlockModels = .{};
            errdefer block_models.deinit(parent.thread_alloc.allocator());

            try blocks_mesh.generate(&block_models, block_arr, 1);

            parent.queue_mutex.lock();
            defer parent.queue_mutex.unlock();

            const step_ptr = parent.queue.getPtr(pos.toKey()) orelse unreachable;
            step_ptr.state = .finished;
            step_ptr.type.generate_mesh.blocks_mesh = blocks_mesh;
            step_ptr.type.generate_mesh.block_models = block_models;
        }

        pub fn calcExposedForBlock(block: *Block, neighbors: std.EnumMap(Block.Side, Block.Type)) void {
            for (std.enums.values(Block.Side)) |side| {
                block.exposed.setValue(side.int(), blk: {
                    const nt = neighbors.get(side) orelse break :blk true;
                    break :blk nt == .none or nt.get(.model_type) == .model;
                });
            }
        }

        pub fn finish(self: @This(), parent: *Pipeline, step: Step) !void {
            const gop = try parent.cm.loaded_chunks.getOrPut(parent.cm.alloc, step.pos.toKey());

            if (gop.found_existing) {
                gop.value_ptr.blocks_mesh.deinit();
                gop.value_ptr.block_models.deinit(parent.thread_alloc.allocator());
            }

            gop.value_ptr.blocks_mesh = self.blocks_mesh;
            gop.value_ptr.block_models = self.block_models;

            try gop.value_ptr.uploadMesh(parent.alloc);

            parent.alloc.destroy(self.block_arr);
            parent.alloc.destroy(self.neighbors);

            _ = parent.queue.remove(step.pos.toKey());
        }

        pub fn cancel(self: *@This(), alloc: std.mem.Allocator) void {
            alloc.destroy(self.block_arr);
            alloc.destroy(self.neighbors);
            if (self.blocks_mesh.vao_id != 0) {
                self.blocks_mesh.deinit();
            }
            self.block_models.deinit(alloc);
        }
    };
};
