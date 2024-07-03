const std = @import("std");
const ztg = @import("zentig");
const Block = @import("block.zig");

const BoundingBox = @This();

min: ztg.Vec3,
max: ztg.Vec3,

pub fn fromBox(center: ztg.Vec3, size: ztg.Vec3) BoundingBox {
    return .{
        .min = center.sub(size.div(2)),
        .max = center.add(size.div(2)),
    };
}

/// Returns a BoundingBox in world space around the block position
pub fn fromBlock(block_pos: Block.Position) BoundingBox {
    const world_pos = block_pos.toWorld();
    return fromBox(ztg.from3(world_pos).add(ztg.splat3(Block.size / 2)), ztg.splat3(Block.size));
}

pub fn setCenter(self: *BoundingBox, center: ztg.Vec3) void {
    const size = (self.max - self.min);
    self.min = center.sub(size.div(2));
    self.max = center.add(size.div(2));
}

pub fn getCenter(self: BoundingBox) ztg.Vec3 {
    return self.max.sub(self.min).div(2);
}

pub fn collides(a: BoundingBox, b: BoundingBox) bool {
    return a.min.x <= b.max.x and
        a.max.x >= b.min.x and
        a.min.y <= b.max.y and
        a.max.y >= b.min.y and
        a.min.z <= b.max.z and
        a.max.z >= b.min.z;
}

pub fn distance(a: BoundingBox, b: BoundingBox) f32 {
    const distances1 = b.min.sub(a.max);
    const distances2 = a.min.sub(b.max);
    const distances = distances1.max(distances2).intoSimd();

    const max_distance = blk: {
        var max_distance: f32 = 0;
        for (0..3) |axis| if (distances[axis] > max_distance) {
            max_distance = distances[axis];
        };
        break :blk max_distance;
    };

    return max_distance;
}

pub fn offsetBy(self: BoundingBox, offset: ztg.Vec3) BoundingBox {
    return .{
        .min = self.min.add(offset),
        .max = self.max.add(offset),
    };
}

pub inline fn getSize(self: BoundingBox) ztg.Vec3 {
    return self.max.sub(self.min);
}

pub inline fn getSizeAxis(self: BoundingBox, axis: usize) f32 {
    return self.max.intoSimd()[axis] - self.min.intoSimd()[axis];
}

pub inline fn getEdge(self: BoundingBox, axis: usize, dir: f32) f32 {
    const size = self.getSizeAxis(axis);
    return (self.max.intoSimd()[axis] - size / 2) - (size * dir / 2);
}

test getEdge {
    const bb = BoundingBox.fromBlock(.{});
    try std.testing.expectEqual(Block.size, bb.getEdge(1, -1));
    try std.testing.expectEqual(0, bb.getEdge(1, 1));
}
