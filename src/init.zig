const ztg = @import("zentig");
const zrl = @import("zrl");
const rl = zrl.rl;

pub const Input = ztg.input.Build(zrl.input.wrapper, enum {
    jump,
    attack,
    use,
    sneak,
    run,
    toggle_flight,
    select_hotbar_slot_1,
    select_hotbar_slot_2,
    select_hotbar_slot_3,
    select_hotbar_slot_4,
    select_hotbar_slot_5,
    select_hotbar_slot_6,
    select_hotbar_slot_7,
    select_hotbar_slot_8,
    select_hotbar_slot_9,
    open_inventory,
    open_chat,
    pause,
    gui_cancel,
    gui_press,
    gui_alt_press,
    gui_mod,
    change_render_distance,
    toggle_debug_info,
    toggle_hud,
    take_screenshot,
}, enum {
    horiz,
    vert,
    mouse_pos,
}, .{});

pub var should_quit = false;

pub const recipes = @import("recipes.zig");

pub const Player = @import("player.zig");

pub const Block = @import("block.zig");
pub const Chunk = @import("chunk.zig");
pub const ChunkManager = @import("chunk_manager.zig");

pub const Inventory = @import("inventory.zig");
pub const ItemPickup = @import("item_pickup.zig");
pub const Item = @import("item.zig").Item;

pub const Chat = @import("chat.zig");

pub const Array2d = @import("array2d.zig").Array2d;
pub const Array3d = @import("array3d.zig").Array3d;
pub const Button = @import("button.zig");

pub const BoundingBox = @import("bounding_box.zig");
pub const BoxCollider = @import("box_collider.zig");

pub fn drawText(text: []const u8, posX: c_int, posY: c_int, font_size: c_int, color: rl.Color) void {
    drawTextV(text, .{ .x = @floatFromInt(posX), .y = @floatFromInt(posY) }, font_size, color);
}

pub fn drawTextV(text: []const u8, pos: rl.Vector2, font_size: c_int, color: rl.Color) void {
    var font_size_ = font_size;

    if (rl.GetFontDefault().texture.id != 0) {
        const default_font_size = 10; // Default Font chars height in pixel
        if (font_size_ < default_font_size) font_size_ = default_font_size;
        const spacing = @divFloor(font_size_, default_font_size);

        drawTextEx(rl.GetFontDefault(), text, pos, font_size_, @floatFromInt(spacing), color);
    }
}

/// Draw text using Font
/// NOTE: chars spacing is NOT proportional to fontSize
pub fn drawTextEx(_font: rl.Font, text: []const u8, position: rl.Vector2, _fontSize: c_int, spacing: f32, tint: rl.Color) void {
    var font = _font;
    const fontSize: f32 = @floatFromInt(_fontSize);

    if (font.texture.id == 0) font = rl.GetFontDefault(); // Security check in case of not valid font

    var textOffsetY: f32 = 0; // Offset between lines (on linebreak '\n')
    var textOffsetX: f32 = 0; // Offset X to next character to draw

    const scaleFactor: f32 = fontSize / @as(f32, @floatFromInt(font.baseSize)); // Character quad scaling factor

    var i: usize = 0;
    while (i < text.len) {
        // Get next codepoint from byte string and glyph index in font
        var codepointByteCount: c_int = 0;
        const codepoint = rl.GetCodepointNext(&text[i], &codepointByteCount);
        const index: usize = @intCast(rl.GetGlyphIndex(font, codepoint));

        if (codepoint == '\n') {
            // NOTE: Line spacing is a global variable, use SetTextLineSpacing() to setup
            const textLineSpacing = 15; // Text vertical line spacing in pixels
            textOffsetY += textLineSpacing;
            textOffsetX = 0.0;
        } else {
            if ((codepoint != ' ') and (codepoint != '\t')) {
                rl.DrawTextCodepoint(font, codepoint, .{ .x = position.x + textOffsetX, .y = position.y + textOffsetY }, fontSize, tint);
            }

            if (font.glyphs[index].advanceX == 0) {
                textOffsetX += (font.recs[index].width * scaleFactor + spacing);
            } else {
                const advance_x: f32 = @floatFromInt(font.glyphs[index].advanceX);
                textOffsetX += (advance_x * scaleFactor + spacing);
            }
        }

        i += @intCast(codepointByteCount); // Move text bytes counter to next codepoint
    }
}
