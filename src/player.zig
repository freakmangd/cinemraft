const std = @import("std");
const ztg = @import("zentig");
const zrl = @import("zrl");
const rl = zrl.rl;
const c = @import("init.zig");

const Player = @This();

pub const Gui = @import("player_gui.zig");

name: []const u8 = "Player",

jump_buffer: f32 = 0,

selected_inventory_slot: u8 = 0,
inventory: c.Inventory = .{},

break_time: ?struct {
    position: c.Block.Position,
    type: c.Block.Type,
    time: f32,
    total_time: f32,
} = null,

const mouse_sensitivity = 0.04;
const max_move_speed = 80;
const max_jump_buffer = 0.1;

var can_fly: bool = false;

pub fn include(comptime wb: *ztg.WorldBuilder) void {
    wb.addComponents(&.{ Player, Camera });
    wb.include(&.{Gui});
    wb.addSystems(.{
        .update = update,
        .draw = draw,
        .collider_update = ztg.after(.body, postColliderUpdate),
    });
}

pub const Camera = struct {
    offset: ztg.Vec3 = .{ .x = 0, .y = c.Block.size * 0.6, .z = 0 },
    camera: rl.Camera = .{
        .target = zrl.vec3(1, 0, 0),
        .up = zrl.vec3(0, 1, 0),
        .fovy = 90,
        .projection = rl.CAMERA_PERSPECTIVE,
    },

    pub fn init(pos: ztg.Vec3) Camera {
        var cam: rl.Camera = .{
            .target = pos.add(.{ .x = 1 }).into(rl.Vector3),
            .up = zrl.vec3(0, 1, 0),
            .fovy = 90,
            .projection = rl.CAMERA_PERSPECTIVE,
        };
        rl.UpdateCameraPro(&cam, pos.into(rl.Vector3), .{}, 1);
        return .{
            .camera = cam,
        };
    }
};

pub fn spawn(com: ztg.Commands, pos: ztg.Vec3) !ztg.EntityHandle {
    return com.newEntWith(.{
        Player{},
        ztg.base.Transform.fromPos(pos),
        c.BoxCollider{
            .bounds = c.BoundingBox.fromBox(.{}, ztg.vec3(c.Block.size * 0.8, c.Block.size * 1.9, c.Block.size * 0.8)),
        },
        Camera.init(pos),
        Gui{},
    });
}

fn update(
    com: ztg.Commands,
    input: c.Input,
    chunks: *c.ChunkManager,
    player_q: ztg.Query(.{ ztg.base.Transform, Player, Player.Camera, Gui, c.BoxCollider }),
) !void {
    for (
        player_q.items(0),
        player_q.items(1),
        player_q.items(2),
        player_q.items(3),
        player_q.items(4),
    ) |tr, player, pc, gui, collider| {
        const dt = rl.GetFrameTime();
        const pos = tr.getPos();

        var movement = ztg.Vec3.zero;
        player.jump_buffer -= dt;

        if (gui.state == .closed) {
            try updateWithInput(
                com,
                input,
                player,
                pc,
                gui,
                chunks,
                collider,
                pos,
                &movement,
            );
        }

        var target = ztg.from3(pc.camera.target);
        target.y = pc.camera.position.y;
        const forward = target.sub(ztg.from3(pc.camera.position)).getNormalized();
        const up = ztg.from3(pc.camera.up).getNormalized();
        const right = forward.cross(up).getNormalized();

        const move_speed: f32 = if (!can_fly and input.isDown(0, .sneak))
            max_move_speed * 0.2
        else if (input.isDown(0, .run))
            max_move_speed * 2
        else
            max_move_speed;

        if (movement.sqrLength() != 0) {
            var desired = right.mul(movement.x * move_speed).add(forward.mul(movement.z * move_speed));
            desired.y = collider.velocity.y;

            collider.velocity = desired;
        } else {
            collider.velocity.x *= 0.2 * dt;
            collider.velocity.z *= 0.2 * dt;
        }

        if (player.jump_buffer > 0) {
            collider.velocity.y = 80;
            player.jump_buffer = 0;
        }

        if (can_fly) {
            collider.velocity.y = movement.y * move_speed;
        } else {
            collider.velocity.y -= 98.5 * 2 * dt;
        }

        collider.enabled = !can_fly and pos.y > -c.Block.size * 2;
    }
}

fn postColliderUpdate(time: ztg.base.Time, q: ztg.Query(.{ ztg.base.Transform, Camera, c.BoxCollider })) void {
    for (q.items(0), q.items(1), q.items(2)) |tr, pc, collider| {
        const cam_pos: ztg.Vec3 = tr.getPos().add(pc.offset);
        pc.camera.position = zrl.fromVec(cam_pos);
        pc.camera.target = ztg.from3(pc.camera.target).add(collider.velocity.mul(time.dt)).into(rl.Vector3);
    }
}

fn updateWithInput(
    com: ztg.Commands,
    input: c.Input,
    player: *Player,
    pc: *Camera,
    gui: *Gui,
    chunks: *c.ChunkManager,
    collider: *c.BoxCollider,
    pos: ztg.Vec3,
    movement: *ztg.Vec3,
) !void {
    const dt = rl.GetFrameTime();

    movement.x = input.getAxis(0, .horiz);
    movement.z = input.getAxis(0, .vert);

    if (can_fly and input.isDown(0, .jump)) movement.y += 1;
    if (can_fly and input.isDown(0, .sneak)) movement.y -= 1;
    movement.setNormalized();

    if (input.isPressed(0, .jump))
        player.jump_buffer = max_jump_buffer;

    for (@intFromEnum(c.Input.Buttons.select_hotbar_slot_1).. //
    @intFromEnum(c.Input.Buttons.select_hotbar_slot_9) + 1) |k| {
        if (input.isPressed(0, @enumFromInt(k))) {
            std.log.info("pressed {}", .{k});
            player.selected_inventory_slot =
                @intCast(k - @intFromEnum(c.Input.Buttons.select_hotbar_slot_1));
            player.break_time = null;
        }
    }

    const mouse_delta = rl.GetMouseDelta();
    rl.UpdateCameraPro(
        &pc.camera,
        .{},
        zrl.vec3(mouse_delta.x * mouse_sensitivity, mouse_delta.y * mouse_sensitivity, 0),
        0,
    );

    const scroll_raw = rl.GetMouseWheelMove();
    if (@abs(scroll_raw) > 0.5) {
        const scroll: i16 = @intFromFloat(std.math.round(-scroll_raw));
        player.selected_inventory_slot = @intCast(
            std.math.clamp(player.selected_inventory_slot + scroll, 0, 8),
        );
        player.break_time = null;
    }

    if (input.isPressed(0, .toggle_flight)) {
        can_fly = !can_fly;
        std.log.info("toggled flight {}", .{can_fly});
    }

    if (input.isPressed(0, .use)) use: {
        const hb = (chunks.hoveredBlock(pc.camera) orelse break :use);

        if (!input.isDown(0, .sneak) and hb.block.type.get(.can_use)) {
            hb.block.onUse(gui);
            break :use;
        }

        const slot = &player.inventory.slots[27 + player.selected_inventory_slot];
        if (slot.* == .empty or slot.filled.count == 0) break :use;

        switch (slot.filled.item) {
            .block => |block_type| {
                const normal_vec: @Vector(3, f32) = @bitCast(hb.ray_collision.normal);
                const place_pos = hb.position.shiftV(@intFromFloat(normal_vec));

                if (collider.bounds.offsetBy(pos).collides(c.BoundingBox.fromBlock(place_pos))) break :use;

                if (try chunks.placeBlockInWorld(com, place_pos, block_type, .{
                    .placed_on = .{
                        .side = c.Block.Side.fromVector(@bitCast(normal_vec)),
                        .block = hb.block,
                    },
                    .placer_pos = pos,
                }) == false) break :use;

                gui.outline_timer = 0;

                if (!can_fly) {
                    slot.filled.count -= 1;
                    if (slot.filled.count == 0) slot.* = .empty;
                }
            },
            .tool => |tool| {
                tool.use(hb);
            },
            .misc => {},
        }
    }

    if ((!can_fly and input.isDown(0, .attack)) or
        (can_fly and input.isPressed(0, .attack)))
    remove_block: {
        const slot = &player.inventory.slots[27 + player.selected_inventory_slot];
        const hb: c.ChunkManager.HoveredBlockHit = chunks.hoveredBlock(pc.camera) orelse {
            player.break_time = null;
            break :remove_block;
        };

        if (can_fly) {
            _ = try chunks.placeBlockInWorld(com, hb.position, .none, .{});
            gui.outline_timer = 0;
            break :remove_block;
        }

        const mining_speed = c.Block.block_info.get(hb.block.type).mining_speed;

        const break_time_mul: f32 = switch (slot.*) {
            .filled => |filled| switch (filled.item) {
                .block => 1,
                .tool => |tool| break_time_mul: {
                    const tool_info = c.Item.Tool.info.getPtrConst(tool.type);
                    if (tool_info.category == hb.block.type.get(.breaking_tool)) {
                        break :break_time_mul c.Item.Tool.mining_speed_mul.get(tool_info.category).get(tool_info.material);
                    }
                    break :break_time_mul 1;
                },
                .misc => 1,
            },
            .empty => 1,
        };

        if (player.break_time) |*bt| {
            if (bt.position.eql(hb.position)) {
                bt.time += dt * break_time_mul;

                if (bt.time >= mining_speed) {
                    _ = try chunks.placeBlockInWorld(com, hb.position, .none, .{});

                    if (slot.getItem(.tool)) |tool| {
                        if (tool.get(.category) == bt.type.get(.breaking_tool)) {
                            slot.filled.item.tool.durability -= 1;
                        }
                    }

                    gui.outline_timer = 0;
                }
            } else {
                bt.* = .{
                    .position = hb.position,
                    .type = hb.block.type,
                    .time = dt,
                    .total_time = mining_speed,
                };
            }
        } else {
            player.break_time = .{
                .position = hb.position,
                .type = hb.block.type,
                .time = dt,
                .total_time = mining_speed,
            };
        }
    } else {
        player.break_time = null;
    }
}

fn draw(player_q: ztg.Query(.{Player})) void {
    for (player_q.items(0)) |_player| {
        const player: *Player = _player;

        if (player.break_time) |bt| {
            const block_world_pos = rl.Vector3Add(bt.position.toWorld(), zrl.vec3splat(c.Block.size / 2));
            rl.DrawCubeV(block_world_pos, zrl.vec3splat(c.Block.size + 0.07), rl.ColorAlpha(rl.BLACK, bt.time / bt.total_time));
        }
    }
}

fn switchHotbarItem(self: *Player, pos: u8) void {
    self.break_time = null;
    self.selected_inventory_slot = pos;
}

pub fn onAdded(self: *Player) void {
    self.inventory.slots[c.Inventory.hotbar_offset..].* = .{
        c.Inventory.Slot.init(.block, .dirt, 64),
        c.Inventory.Slot.init(.block, .wood, 64),
        c.Inventory.Slot.init(.tool, .stone_shovel, 1),
        c.Inventory.Slot.init(.tool, .stone_pickaxe, 1),
        c.Inventory.Slot.init(.tool, .stone_axe, 1),
        c.Inventory.Slot.init(.block, .crafting_table, 1),
        c.Inventory.Slot.init(.block, .chest, 1),
        .empty,
        .empty,
    };
}
