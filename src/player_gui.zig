const std = @import("std");
const ztg = @import("zentig");
const zrl = @import("zrl");
const rl = zrl.rl;
const c = @import("init.zig");
const Chunk = c.Chunk;
const Block = c.Block;
const ChunkManager = c.ChunkManager;
const Player = c.Player;
const Button = c.Button;
const Inventory = c.Inventory;
const BoxCollider = c.BoxCollider;

const Gui = @This();

hidden: bool = false,
draw_debug_info: bool = true,

outline_timer: f32 = 0,
hovered_block: ?rl.Vector3 = null,

ct_craft_slots: [3 * 3]Inventory.Slot = .{.empty} ** (3 * 3),
ct_output_slot: Inventory.OutputSlot = .{ .slot = .empty },

chat: c.Chat,

state: union(enum) {
    closed,
    paused,
    inventory,
    chat,
    crafting_table,
    chest: *c.Block.Type.ChestData,
} = .closed,

pub fn include(wb: *ztg.WorldBuilder) void {
    wb.addSystems(.{
        .update = update,
        .draw = draw,
        .gui = drawGui,
    });
    wb.addComponents(&.{Gui});
    wb.addResource(TimingInfo, .{});
}

const inventory_start_pos = ztg.vec2(200, 350);

const continue_button = Button{
    .rect = zrl.rectangle(10, 10, 70, 30),
    .text = "CONTINUE",
};
const quit_button = Button{
    .rect = zrl.rectangle(10, 50, 70, 30),
    .text = "QUIT",
};

pub const TimingInfo = struct {
    update_ms: f32 = 0,
    draw_ms: f32 = 0,
    frame_count: f32 = 1,
};

pub fn onRemoved(gui: *Gui) !void {
    gui.chat.deinit();
}

fn update(
    com: ztg.Commands,
    alloc: std.mem.Allocator,
    input: c.Input,
    chunks: *ChunkManager,
    player_q: ztg.Query(.{ ztg.base.Transform, Player, Player.Camera, Gui }),
) !void {
    for (
        player_q.items(0),
        player_q.items(1),
        player_q.items(2),
        player_q.items(3),
    ) |tr, player, pc, _gui| {
        const gui: *Gui = _gui;

        if (input.isPressed(0, .toggle_debug_info)) {
            gui.draw_debug_info = !gui.draw_debug_info;
        }

        if (input.isPressed(0, .take_screenshot)) {
            var buf: [64]u8 = undefined;
            const file_name = try std.fmt.bufPrintZ(&buf, "screenshot{}.png", .{std.time.milliTimestamp()});
            rl.TakeScreenshot(file_name);
        }

        if (input.isPressed(0, .toggle_hud)) {
            gui.hidden = !gui.hidden;
        }

        const ms_pos = rl.GetMousePosition();

        const closed = try gui.chat.update(com, tr.getPos(), player);

        switch (gui.state) {
            .closed => {
                if (input.isPressed(0, .open_inventory)) {
                    gui.state = .inventory;
                    rl.EnableCursor();
                } else if (input.isPressed(0, .pause)) {
                    gui.state = .paused;
                    rl.EnableCursor();
                } else if (input.isReleased(0, .open_chat)) {
                    gui.state = .chat;
                    gui.chat.open();
                    rl.EnableCursor();
                } else if (rl.IsKeyReleased(rl.KEY_SLASH)) {
                    gui.state = .chat;
                    gui.chat.open();
                    try gui.chat.text_box.append(alloc, '/');
                    rl.EnableCursor();
                }

                gui.outline_timer -= rl.GetFrameTime();

                if (gui.outline_timer <= 0) {
                    gui.outline_timer = 0.05;
                    const bh = chunks.hoveredBlock(pc.camera) orelse {
                        gui.hovered_block = null;
                        continue;
                    };
                    gui.hovered_block = bh.position.toWorld();
                }
            },
            .inventory => {
                player.inventory.update(inventory_start_pos, input, ms_pos);
                player.inventory.updateMiniCrafter(inventory_start_pos, input, ms_pos);

                if (input.isPressed(0, .open_inventory) or input.isPressed(0, .gui_cancel)) {
                    gui.state = .closed;
                    try player.inventory.close(tr.getPos(), com);
                    rl.DisableCursor();
                }
            },
            .paused => {
                if (continue_button.isPressedAt(input, ms_pos)) {
                    gui.state = .closed;
                    rl.DisableCursor();
                } else if (quit_button.isPressedAt(input, ms_pos)) {
                    c.should_quit = true;
                }

                if (input.isPressed(0, .gui_cancel) or input.isPressed(0, .pause)) {
                    gui.state = .closed;
                    rl.DisableCursor();
                }
            },
            .chat => {
                if (closed) {
                    try gui.chat.close();

                    gui.state = .closed;
                    rl.DisableCursor();
                }
            },
            .crafting_table => {
                player.inventory.update(inventory_start_pos, input, ms_pos);
                crafting_table_gui.update(gui, &player.inventory, input, ms_pos);

                if (input.isPressed(0, .open_inventory) or input.isPressed(0, .gui_cancel)) {
                    gui.state = .closed;
                    rl.DisableCursor();
                    try crafting_table_gui.close(com, tr.getPos(), gui, &player.inventory);
                }
            },
            .chest => |chest_data| {
                player.inventory.update(inventory_start_pos, input, ms_pos);
                chest_gui.update(&player.inventory, chest_data, input, ms_pos);

                if (input.isPressed(0, .open_inventory) or input.isPressed(0, .gui_cancel)) {
                    gui.state = .closed;
                    rl.DisableCursor();
                }
            },
        }
    }
}

fn draw(q: ztg.Query(.{Gui})) void {
    for (q.items(0)) |gui| {
        if (gui.hidden) continue;

        if (gui.hovered_block) |hb| {
            rl.rlSetLineWidth(5);
            rl.DrawCubeWiresV(rl.Vector3Add(hb, zrl.vec3splat(Block.size / 2)), zrl.vec3splat(Block.size), rl.GRAY);
        }
    }
}

fn drawGui(player_q: ztg.Query(.{ ztg.base.Transform, Player, Player.Camera, Gui, BoxCollider }), timing_info: *TimingInfo) !void {
    const tr: *ztg.base.Transform = player_q.first(0);
    const player: *Player = player_q.first(1);
    const pc: *Player.Camera = player_q.first(2);
    const gui: *Gui = player_q.first(3);
    const collider: *BoxCollider = player_q.first(4);

    const center_x = @divFloor(rl.GetScreenWidth(), 2);
    const center_y = @divFloor(rl.GetScreenHeight(), 2);

    if (!gui.hidden) {
        gui.chat.drawGui();

        const start_x: f32 = @floatFromInt(center_x - (Inventory.hotbar_visual_len / 2));
        const y: f32 = @floatFromInt(rl.GetScreenHeight() - Inventory.hotbar_item_size - 10);
        player.inventory.drawHotbar(ztg.vec2(start_x, y), player.selected_inventory_slot);
    }

    switch (gui.state) {
        .closed => {},
        .paused => {
            rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.ColorAlpha(rl.BLACK, 0.6));
            continue_button.draw();
            quit_button.draw();
        },
        .inventory => {
            player.inventory.drawMiniCrafter(inventory_start_pos);
            player.inventory.drawOpen(inventory_start_pos);
        },
        .chat => {},
        .crafting_table => crafting_table_gui.draw(gui, &player.inventory),
        .chest => |chest_data| chest_gui.draw(&player.inventory, chest_data),
    }

    if (gui.hidden) return;

    rl.DrawCircle(center_x, center_y, 2, rl.GRAY);

    try gui.drawDebugInfo(pc, tr, collider, timing_info);
}

fn drawDebugInfo(
    gui: *Gui,
    pc: *Player.Camera,
    tr: *ztg.base.Transform,
    collider: *BoxCollider,
    timing_info: *TimingInfo,
) !void {
    const pos = tr.getPos();
    var text_buf: [64]u8 = undefined;

    if (gui.draw_debug_info) {
        rl.DrawFPS(0, 0);

        const ms_text = std.fmt.bufPrintZ(
            &text_buf,
            "Update: {d:.2}ms\nDraw: {d:.2}ms",
            .{ timing_info.update_ms / (1000 * timing_info.frame_count), timing_info.draw_ms / (1000 * timing_info.frame_count) },
        ) catch "...";
        rl.DrawText(ms_text, 0, 20, 20, rl.GREEN);

        const player_chunk = Chunk.Position.fromWorld(pos.into(rl.Vector3));
        const player_block = Block.Position.fromWorld(pos.into(rl.Vector3));
        const chunk_text = std.fmt.bufPrintZ(
            &text_buf,
            "Chunk {} {}\nBlock {} {} {}",
            .{ player_chunk.x, player_chunk.z, player_block.x, player_block.y, player_block.z },
        ) catch "...";
        rl.DrawText(chunk_text, 0, 60, 20, rl.GREEN);

        const vel_text = std.fmt.bufPrintZ(&text_buf, "Velocity {d:.2}", .{collider.velocity}) catch "...";
        rl.DrawText(vel_text, 0, 100, 20, rl.GREEN);

        const target_text = std.fmt.bufPrintZ(&text_buf, "Target {d:.2} {d:.2} {d:.2}", .{
            pos.x - pc.camera.target.x,
            pos.y - pc.camera.target.y,
            pos.z - pc.camera.target.z,
        }) catch "...";
        rl.DrawText(target_text, 0, 120, 20, rl.GREEN);
    }

    if (timing_info.frame_count > 100) {
        timing_info.update_ms = 0;
        timing_info.draw_ms = 0;
        timing_info.frame_count = 1;
    }
}

pub const crafting_table_gui = struct {
    const pos = inventory_start_pos.sub(.{ .y = 200 });

    pub fn open(gui: *Gui) void {
        gui.state = .crafting_table;
        rl.EnableCursor();
    }

    fn close(com: ztg.Commands, player_pos: ztg.Vec3, gui: *Gui, inventory: *Inventory) !void {
        for (&gui.ct_craft_slots) |*slot| {
            if (slot.* == .filled) {
                const remaining = inventory.giveItem(slot.filled.item, slot.filled.count);
                _ = try c.ItemPickup.spawn(com, player_pos, .{}, remaining, slot.filled.item);
                slot.* = .empty;
            }
        }
    }

    fn update(gui: *Gui, inventory: *Inventory, input: c.Input, ms_pos: rl.Vector2) void {
        const hit = Inventory.Slot.updateGrid(
            &gui.ct_craft_slots,
            input,
            &inventory.dragging_slot,
            3,
            pos,
            ms_pos,
            &inventory.slots,
        );
        if (hit) gui.ct_output_slot = .{ .slot = c.recipes.match(&gui.ct_craft_slots, 3) };

        if (input.isPressed(0, .gui_press)) {
            gui.ct_output_slot.leftClick(
                input,
                inventory,
                &inventory.dragging_slot,
                &gui.ct_craft_slots,
                pos.add(.{ .x = Inventory.hotbar_item_size * 4 }),
                ms_pos,
            );
        }
        if (input.isPressed(0, .gui_press) or input.isPressed(0, .gui_alt_press)) {
            gui.ct_output_slot = .{ .slot = c.recipes.match(&gui.ct_craft_slots, 3) };
        }
    }

    fn draw(gui: *Gui, inventory: *Inventory) void {
        Inventory.Slot.drawGrid(&gui.ct_craft_slots, pos, 3);
        gui.ct_output_slot.slot.draw(
            Inventory.Slot.singleRect(pos.add(.{ .x = Inventory.hotbar_item_size * 4 })),
            rl.LIGHTGRAY,
        );
        inventory.drawOpen(inventory_start_pos);
    }
};

pub const chest_gui = struct {
    const pos = inventory_start_pos.sub(.{ .y = 250 });

    pub fn open(gui: *Gui, chest_data: *c.Block.Type.ChestData) void {
        gui.state = .{ .chest = chest_data };
        rl.EnableCursor();
    }

    fn update(inventory: *Inventory, chest_data: *c.Block.Type.ChestData, input: c.Input, ms_pos: rl.Vector2) void {
        _ = Inventory.Slot.updateGrid(
            &chest_data.items,
            input,
            &inventory.dragging_slot,
            Inventory.inventory_width,
            pos,
            ms_pos,
            &inventory.slots,
        );
    }

    fn draw(inventory: *Inventory, chest_data: *c.Block.Type.ChestData) void {
        Inventory.Slot.drawGrid(&chest_data.items, pos, Inventory.inventory_width);
        inventory.drawOpen(inventory_start_pos);
    }
};

pub const OverlayCam = struct {
    arm: rl.Model,
    render_texture: rl.RenderTexture2D,
    gui: *Gui,

    cam3d: rl.Camera3D = .{
        .target = zrl.vec3(0, 0, 0),
        .up = zrl.vec3up,
        .fovy = 23,
        .projection = rl.CAMERA_PERSPECTIVE,
        .position = zrl.vec3(0, 0, 10),
    },

    pub fn init(gui: *Gui) OverlayCam {
        return .{
            .arm = rl.LoadModel("assets/models/arm.obj"),
            .render_texture = rl.LoadRenderTexture(rl.GetScreenWidth(), rl.GetScreenHeight()),
            .gui = gui,
        };
    }

    pub fn render(self: OverlayCam) void {
        if (self.gui.hidden) return;

        rl.BeginTextureMode(self.render_texture);
        rl.ClearBackground(rl.BLANK);

        rl.BeginMode3D(self.cam3d);
        rl.DrawModel(
            self.arm,
            zrl.vec3splat(0),
            1,
            rl.WHITE,
        );
        rl.EndMode3D();

        rl.EndTextureMode();
    }

    pub fn draw(self: OverlayCam) void {
        if (self.gui.hidden) return;

        rl.DrawTextureRec(
            self.render_texture.texture,
            zrl.rectangle(
                0,
                0,
                @floatFromInt(self.render_texture.texture.width),
                @floatFromInt(-self.render_texture.texture.height),
            ),
            zrl.vec2(0, 0),
            rl.WHITE,
        );
    }
};
