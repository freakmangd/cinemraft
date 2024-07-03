const std = @import("std");
const ztg = @import("zentig");
const zrl = @import("zrl");
const rl = zrl.rl;
const c = @import("init.zig");
const Block = c.Block;
const BoundingBox = c.BoundingBox;
const ChunkManager = c.ChunkManager;

const BoxCollider = @This();

bounds: BoundingBox,

enabled: bool = true,
velocity: ztg.Vec3 = .{},
friction: f32 = 0,

pub fn include(wb: *ztg.WorldBuilder) void {
    wb.addComponents(&.{BoxCollider});
    wb.addStage(.collider_update);
    wb.addSystems(.{
        .collider_update = update,
        .draw = draw,
    });
}

fn update(time: ztg.base.Time, chunks: ChunkManager, q: ztg.Query(.{ BoxCollider, ztg.base.Transform })) void {
    for (q.items(0), q.items(1)) |self, tr| {
        const pos = tr.getPos().intoSimd();
        var velocity = self.velocity.intoSimd();

        if (!self.enabled) {
            tr.setPos(ztg.from3(pos).add(ztg.from3(velocity).mul(time.dt)));
            continue;
        }

        const bb = self.bounds.offsetBy(tr.getPos());

        for ([3][3]usize{
            .{ 1, 0, 2 },
            .{ 0, 1, 2 },
            .{ 2, 1, 0 },
        }) |axes| {
            const check_axis, const axis_a, const axis_b = axes;
            if (velocity[check_axis] == 0) continue;

            const check_dir_f: f32 = std.math.sign(velocity[check_axis]);
            const check_dir: i8 = @intFromFloat(check_dir_f);
            if (check_dir == 0) continue;

            const half_size = bb.getSizeAxis(check_axis) / 2;
            const outer_check_point: f32 = pos[check_axis] + half_size * check_dir_f;

            const check = checkRange(bb, pos, velocity, axis_a, axis_b, check_axis, time.dt);

            var block_check = check.min_block_check;
            outer: while (block_check != check.max_block_check + check_dir * 2) : (block_check += check_dir) {
                var block_a = check.min_block_a;
                while (block_a <= check.max_block_a) : (block_a += 1) {
                    var block_b = check.min_block_b;
                    while (block_b <= check.max_block_b) : (block_b += 1) {
                        var block_pos_vec: @Vector(3, i64) = undefined;
                        block_pos_vec[axis_a] = block_a;
                        block_pos_vec[axis_b] = block_b;
                        block_pos_vec[check_axis] = block_check;
                        const block_pos = Block.Position.fromVector(block_pos_vec);
                        const block = chunks.getBlockAtBlockPos(block_pos) orelse continue;

                        if (block.type == .none) continue;

                        const block_bb = BoundingBox.fromBlock(block_pos);
                        var offset: @Vector(3, f32) = @splat(0);
                        offset[check_axis] = velocity[check_axis] * time.dt;

                        if (bb.offsetBy(ztg.from3(offset)).collides(block_bb)) {
                            //std.log.info("hit {}, pos {d}, mul {d}", .{
                            //    block_pos,
                            //    block_bb.getEdge(check_axis, check_dir_f) / Block.size,
                            //    @abs(block_bb.getEdge(check_axis, check_dir_f) - outer_check_point) / velocity[check_axis],
                            //});
                            velocity[check_axis] *= @abs(block_bb.getEdge(check_axis, check_dir_f) - outer_check_point) / velocity[check_axis];
                            break :outer;
                        }
                    }
                }
            }

            tr.setPos(ztg.from3(pos + velocity * @as(@Vector(3, f32), @splat(time.dt))));
            self.velocity = ztg.from3(velocity);
        }
    }
}

fn draw(q: ztg.Query(.{ BoxCollider, ztg.base.Transform })) void {
    _ = q; // autofix
    //for (q.items(0), q.items(1)) |self, tr| {
    //    const pos = tr.getPos().into(rl.Vector3);
    //    rl.DrawCubeWiresV(pos, @bitCast(self.bounds.getSize()), rl.RED);
    //    rl.DrawSphere(pos, 0.5, rl.BLUE);
    //}
}

fn checkRange(
    bb: BoundingBox,
    pos: @Vector(3, f32),
    velocity: @Vector(3, f32),
    axis_a: usize,
    axis_b: usize,
    check_axis: usize,
    dt: f32,
) struct {
    min_block_a: i64,
    max_block_a: i64,
    min_block_b: i64,
    max_block_b: i64,
    min_block_check: i64,
    max_block_check: i64,
} {
    const half_size = bb.getSizeAxis(check_axis) / 2;
    const check_dir_f: f32 = std.math.sign(velocity[check_axis]);

    return .{
        .min_block_a = @intFromFloat(@round((bb.min.intoSimd()[axis_a] / Block.size) - 1)),
        .max_block_a = @intFromFloat(@round((bb.max.intoSimd()[axis_a] / Block.size) + 1)),
        .min_block_b = @intFromFloat(@round((bb.min.intoSimd()[axis_b] / Block.size) - 1)),
        .max_block_b = @intFromFloat(@round((bb.max.intoSimd()[axis_b] / Block.size) + 1)),
        // block at the end of objects's velocity
        .max_block_check = @intFromFloat(@round(((pos[check_axis] + velocity[check_axis] * dt + half_size * check_dir_f)) / Block.size)),
        // block at the objects's feet/head/front/back
        .min_block_check = @intFromFloat(@round((pos[check_axis] + half_size * check_dir_f) / Block.size)),
    };
}

//test checkRange {
//    const size = 3;
//    const bb = BoundingBox.fromBox(@splat(0), @splat(size));
//
//    const pos: @Vector(3, f32) = .{ 0, Block.size * 1.5, 0 };
//
//    const check = checkRange(bb, pos, .{ 0, -10, 0 }, 0, 2, 1, 1);
//
//    try std.testing.expectEqual(-1, check.min_block_a);
//    try std.testing.expectEqual(1, check.max_block_a);
//    try std.testing.expectEqual(-1, check.min_block_b);
//    try std.testing.expectEqual(1, check.max_block_b);
//    try std.testing.expectEqual(-2, check.min_block_check);
//    try std.testing.expectEqual(-12, check.max_block_check);
//}
