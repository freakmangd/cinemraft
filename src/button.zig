const zrl = @import("zrl");
const rl = zrl.rl;
const c = @import("init.zig");

const Button = @This();

rect: rl.Rectangle,
back_color: rl.Color = rl.LIGHTGRAY,
text: [:0]const u8,
text_color: rl.Color = rl.DARKGRAY,
font_size: u16 = 20,

pub fn draw(self: Button) void {
    rl.DrawRectangleRec(self.rect, self.back_color);
    rl.DrawText(self.text, @intFromFloat(self.rect.x), @intFromFloat(self.rect.y), self.font_size, self.text_color);
}

pub fn isPressedAt(self: Button, input: c.Input, mouse_pos: rl.Vector2) bool {
    return input.isPressed(0, .gui_press) and rl.CheckCollisionPointRec(mouse_pos, self.rect);
}
