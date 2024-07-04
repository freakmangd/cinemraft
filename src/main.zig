const std = @import("std");
const ztg = @import("zentig");
const zrl = @import("zrl");
const rl = zrl.rl;
const c = @import("init.zig");

const World = ztg.WorldBuilder.init(&.{
    ztg.base,
    zrl,
    @This(),
    c.Input,
    c.Block,
    c.ChunkManager,
    c.BoxCollider,
    c.ItemPickup,
    c.Player,
}).Build();

pub fn include(wb: *ztg.WorldBuilder) void {
    wb.addStage(.gui);
    wb.addSystems(.{
        .init = .{ c.Item.Tool.setup, c.Item.Misc.setup },
        .load = load,
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 16 }){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    rl.SetTraceLogLevel(rl.LOG_WARNING);

    rl.InitWindow(1280, 720, "ok");
    defer rl.CloseWindow();

    rl.SetExitKey(rl.KEY_NULL);
    rl.SetTargetFPS(500);
    rl.SetWindowMonitor(0);
    rl.DisableCursor();

    var world = try World.init(alloc);
    defer world.deinit();

    try world.runStage(.load);

    const player_cam_query = try world.query(alloc, ztg.Query(.{ c.Player.Camera, c.Player.Gui }));
    defer player_cam_query.deinit(alloc);

    const player_cam: *c.Player.Camera = player_cam_query.single(0);
    var player_overlay_cam = c.Player.Gui.OverlayCam.init(player_cam_query.single(1));

    const timing_info = world.getResPtr(c.Player.Gui.TimingInfo);

    while (!rl.WindowShouldClose() and !c.should_quit) {
        const update_start = std.time.microTimestamp();

        try world.runUpdateStages();
        try world.runStage(.collider_update);

        const draw_start = std.time.microTimestamp();

        player_overlay_cam.render();

        rl.BeginDrawing();
        rl.ClearBackground(rl.BLUE);
        rl.rlSetLineWidth(5);

        rl.BeginMode3D(player_cam.camera);
        try world.runStage(.draw);
        rl.EndMode3D();

        player_overlay_cam.draw();

        try world.runStage(.gui);

        rl.EndDrawing();

        //c.Block.SHIT();

        timing_info.update_ms += @floatFromInt(draw_start - update_start);
        timing_info.draw_ms += @floatFromInt(std.time.microTimestamp() - draw_start);
        timing_info.frame_count += 1;

        world.cleanForNextFrame();
    }
}

fn load(com: ztg.Commands, input: *c.Input) !void {
    _ = try c.Player.spawn(com, ztg.vec3(0, 24 * c.Block.size, 0));

    try input.addBindings(0, .{ .axes = .{
        .horiz = &.{zrl.input.kbAxis(rl.KEY_D, rl.KEY_A)},
        .vert = &.{zrl.input.kbAxis(rl.KEY_W, rl.KEY_S)},
    }, .buttons = .{
        .jump = &.{zrl.input.kbButton(rl.KEY_SPACE)},
        .attack = &.{zrl.input.msButton(0)},
        .use = &.{zrl.input.msButton(1)},
        .sneak = &.{zrl.input.kbButton(rl.KEY_LEFT_SHIFT)},
        .run = &.{zrl.input.kbButton(rl.KEY_LEFT_CONTROL)},
        .toggle_flight = &.{zrl.input.kbButton(rl.KEY_Q)},
        .select_hotbar_slot_1 = &.{zrl.input.kbButton(rl.KEY_ONE)},
        .select_hotbar_slot_2 = &.{zrl.input.kbButton(rl.KEY_TWO)},
        .select_hotbar_slot_3 = &.{zrl.input.kbButton(rl.KEY_THREE)},
        .select_hotbar_slot_4 = &.{zrl.input.kbButton(rl.KEY_FOUR)},
        .select_hotbar_slot_5 = &.{zrl.input.kbButton(rl.KEY_FIVE)},
        .select_hotbar_slot_6 = &.{zrl.input.kbButton(rl.KEY_SIX)},
        .select_hotbar_slot_7 = &.{zrl.input.kbButton(rl.KEY_SEVEN)},
        .select_hotbar_slot_8 = &.{zrl.input.kbButton(rl.KEY_EIGHT)},
        .select_hotbar_slot_9 = &.{zrl.input.kbButton(rl.KEY_NINE)},
        .open_inventory = &.{zrl.input.kbButton(rl.KEY_E)},
        .open_chat = &.{zrl.input.kbButton(rl.KEY_ENTER)},
        .pause = &.{zrl.input.kbButton(rl.KEY_ESCAPE)},
        .gui_cancel = &.{zrl.input.kbButton(rl.KEY_ESCAPE)},
        .gui_press = &.{zrl.input.msButton(0)},
        .gui_alt_press = &.{zrl.input.msButton(1)},
        .gui_mod = &.{zrl.input.kbButton(rl.KEY_LEFT_SHIFT)},
        .change_render_distance = &.{zrl.input.kbButton(rl.KEY_F10)},
        .toggle_debug_info = &.{zrl.input.kbButton(rl.KEY_F3)},
        .toggle_hud = &.{zrl.input.kbButton(rl.KEY_F1)},
        .take_screenshot = &.{zrl.input.kbButton(rl.KEY_F2)},
    } });
}

test {
    _ = @import("block.zig");
    _ = @import("chunk.zig");
    _ = c.BoxCollider;
    _ = c.BoundingBox;
}
