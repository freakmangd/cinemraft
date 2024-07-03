const std = @import("std");
const ztg = @import("zentig");
const zrl = @import("zrl");
const rl = zrl.rl;
const c = @import("init.zig");
const Player = c.Player;
const Block = c.Block;
const Item = c.Item;
const BoxCollider = c.BoxCollider;
const BoundingBox = c.BoundingBox;
const ChunkManager = c.ChunkManager;

const ItemPickup = @This();

item: Item,
count: u8 = 1,

const size = 2;

const magnet_range = 20;
const magnet_speed = 5;

const pickup_range = 10;

pub fn include(comptime wb: *ztg.WorldBuilder) void {
    wb.addComponents(&.{ItemPickup});
    wb.addSystems(.{
        .update = update,
        .draw = draw,
    });
}

pub fn spawn(com: ztg.Commands, pos: ztg.Vec3, vel: ztg.Vec3, count: u8, item: Item) !ztg.EntityHandle {
    return com.newEntWith(.{
        ztg.base.Transform.fromPos(pos),
        ItemPickup{ .item = item, .count = count },
        BoxCollider{
            .velocity = vel,
            .bounds = BoundingBox.fromBox(.{}, ztg.Vec3.splat(size)),
        },
    });
}

fn update(com: ztg.Commands, self_q: ztg.Query(.{ ztg.Entity, ztg.base.Transform, ItemPickup, BoxCollider }), p_q: ztg.Query(.{ ztg.base.Transform, Player })) !void {
    for (self_q.items(0), self_q.items(1), self_q.items(2), self_q.items(3)) |ent, tr, pickup, collider| {
        for (p_q.items(0), p_q.items(1)) |player_tr, _player| {
            const player: *Player = _player;

            const pos = tr.getPos();
            const player_pos = player_tr.getPos();
            const sqr_dist = player_pos.sqrDistance(pos);

            if (player.inventory.slotFor(pickup.item)) |slot| {
                if (sqr_dist < pickup_range * pickup_range) {
                    pickup.count = slot.give(pickup.item, pickup.count);
                    if (pickup.count == 0) try com.removeEnt(ent);
                } else if (sqr_dist < magnet_range * magnet_range) {
                    collider.velocity.addEql(pos.directionTo(player_pos).mul(magnet_speed));
                }
            }

            const dt = rl.GetFrameTime();
            collider.velocity.addEql(.{ .y = -9.8 * 3 * dt });
        }
    }
}

fn draw(self_q: ztg.Query(.{ ztg.base.Transform, ItemPickup })) void {
    for (self_q.items(0), self_q.items(1)) |tr, _pickup| {
        const pickup: *ItemPickup = _pickup;

        //rl.DrawSphere(pickup.position.into(rl.Vector3), 1, rl.BLUE);
        //rl.DrawCubeWiresV(pickup.position.add(ztg.Vec3.splat(Block.size / 2)).into(rl.Vector3), zrl.vec3splat(Block.size), rl.RED);

        switch (pickup.item) {
            .block, .tool, .misc => rl.DrawCube(tr.getPos().into(rl.Vector3), size, size, size, rl.WHITE),
        }
    }
}
