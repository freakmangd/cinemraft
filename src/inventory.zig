const std = @import("std");
const ztg = @import("zentig");
const zrl = @import("zrl");
const rl = zrl.rl;
const c = @import("init.zig");
const recipes = c.recipes;
const Block = c.Block;
const Item = c.Item;
const Tool = Item.Tool;
const ItemPickup = c.ItemPickup;
const Player = c.Player;

const Inventory = @This();

slots: [len]Slot = .{.empty} ** len,
dragging_slot: Slot = .empty,

crafting_slots: [4]Slot = .{.empty} ** 4,
crafting_output: OutputSlot = .{ .slot = .empty },

pub const inventory_width = 9;
pub const inventory_rows = 4;
/// the last row is the hotbar
pub const hotbar_offset = inventory_width * (inventory_rows - 1);

pub const len = inventory_rows * inventory_width;

pub const hotbar_item_size = 50;
pub const hotbar_visual_len = 9 * hotbar_item_size;

const crafting_slots_offset = 500;

comptime {
    //@compileLog(@sizeOf(union(enum) {
    //    filled: struct {
    //        item: Item,
    //        count: u8,
    //    },
    //    empty,
    //}), @sizeOf(struct {
    //    item: union(enum) {
    //        block: Block.Type,
    //        tool: Tool,
    //        none,
    //    },
    //    count: u8,
    //}));
}

pub const OutputSlot = struct {
    slot: Slot,

    pub fn draw(self: OutputSlot, pos: ztg.Vec2) void {
        const rect = Inventory.Slot.gridRect(pos, 0, 1);
        self.slot.draw(rect, rl.LIGHTGRAY);
    }

    pub fn leftClick(
        self: *OutputSlot,
        input: c.Input,
        inventory: *Inventory,
        dragging_slot: *Slot,
        crafting_slots: []Slot,
        pos: ztg.Vec2,
        ms_pos: rl.Vector2,
    ) void {
        if (self.slot == .empty or !rl.CheckCollisionPointRec(ms_pos, Inventory.Slot.gridRect(pos, 0, 1))) return;

        if (input.isPressed(0, .gui_mod)) {
            self.takeAll(inventory, crafting_slots);
        } else {
            self.takeOne(dragging_slot, crafting_slots);
        }
    }

    fn takeAll(self: *OutputSlot, inventory: *Inventory, crafting_slots: []Slot) void {
        const amount = blk: {
            var amount: ?u8 = null;
            for (crafting_slots) |slot| {
                const count = slot.getCount();
                if (count > 0)
                    amount = @min(amount orelse 255, count);
            }
            break :blk amount orelse return;
        };

        const s = &self.slot.filled;

        var remaining = amount;
        var output_slot: ?*Slot = undefined;
        while (remaining > 0) : (remaining -= 1) {
            output_slot = inventory.slotFor(s.item) orelse break;
            _ = output_slot.?.give(s.item, s.count);
        }

        for (crafting_slots) |*slot| {
            slot.remove(amount - remaining);
        }
    }

    fn takeOne(self: *OutputSlot, dragging_slot: *Slot, crafting_slots: []Slot) void {
        const s = &self.slot.filled;

        if (dragging_slot.* == .empty) {
            std.mem.swap(Inventory.Slot, dragging_slot, &self.slot);
        } else if (dragging_slot.filled.item.eqlType(s.item) and dragging_slot.filled.count + s.count < dragging_slot.filled.item.maxStack()) {
            const remaining = dragging_slot.give(dragging_slot.filled.item, s.count);
            s.count = remaining;
            if (s.count == 0) self.slot = .empty;
        } else return;

        // TODO: maybe some recipes take more than one block in a slot?
        for (crafting_slots) |*slot| slot.remove(1);
    }
};

pub const Slot = union(enum) {
    filled: Filled,
    empty,

    pub const Filled = struct {
        item: Item,
        count: u8,
    };

    pub fn init(
        comptime outer_type: std.meta.Tag(Item),
        inner_type: switch (outer_type) {
            .block => Block.Type,
            .tool => Tool.Type,
            .misc => Item.Misc,
        },
        count: u8,
    ) Slot {
        if (count == 0) return .empty;
        return .{ .filled = .{
            .item = Item.init(outer_type, inner_type),
            .count = count,
        } };
    }

    pub fn getItem(self: *Slot, comptime variant: std.meta.Tag(Item)) ?*std.meta.TagPayload(Item, variant) {
        if (self.* == .empty or self.filled.item != variant) return null;
        return &@field(self.filled.item, @tagName(variant));
    }

    pub fn getCount(self: Slot) u8 {
        return switch (self) {
            .empty => 0,
            .filled => |f| f.count,
        };
    }

    pub fn give(self: *Slot, item: Item, count: u8) u8 {
        if (self.* == .filled and !self.filled.item.eqlType(item)) {
            std.log.err("Tried to give a slot {} even tho it contains {}", .{ item, self.filled.item });
            return count;
        }

        const max_stack = item.maxStack();

        switch (self.*) {
            .filled => |*self_slot| {
                const orig = self_slot.count;
                self_slot.count = @min(self_slot.count + count, max_stack);
                return count - (self_slot.count - orig);
            },
            .empty => {
                if (count > 0) {
                    self.* = .{ .filled = .{ .item = item, .count = @min(count, max_stack) } };
                }
                return count - @min(max_stack, count);
            },
        }
    }

    pub fn remove(self: *Slot, count: u8) void {
        if (self.* == .empty) {
            return;
        }

        if (self.filled.count < count)
            std.log.warn("Tried to remove more than we have", .{});

        self.filled.count -|= count;
        if (self.filled.count == 0) self.* = .empty;
    }

    pub fn interact(
        self: *Slot,
        input: c.Input,
        dragging_slot: *Slot,
        shift_click_slots: []Slot,
    ) void {
        if (input.isPressed(0, .gui_press)) {
            self.leftClick(input, dragging_slot, shift_click_slots);
        } else if (input.isPressed(0, .gui_alt_press)) {
            self.rightClick(dragging_slot);
        }
    }

    pub fn leftClick(self: *Slot, input: c.Input, dragging: *Slot, shift_click_slots: []Slot) void {
        if (self.* == .filled and input.isDown(0, .gui_mod)) {
            self.filled.count = Slot.giveAll(shift_click_slots, self.filled.item, self.filled.count);
            if (self.filled.count == 0) self.* = .empty;
            return;
        }

        if (dragging.* == .empty or self.* == .empty) {
            std.mem.swap(Inventory.Slot, dragging, self);
            return;
        }

        const self_slot = &self.filled;
        const drag_slot = &dragging.filled;
        const max_stack = self_slot.item.maxStack();

        if (self_slot.item.eqlType(drag_slot.item) and self_slot.count < max_stack) {
            const amount_to_take = @min(max_stack - self_slot.count, drag_slot.count);
            self_slot.count += amount_to_take;
            dragging.remove(amount_to_take);
        } else {
            std.mem.swap(Inventory.Slot, dragging, self);
        }
    }

    pub fn rightClick(self: *Slot, dragging: *Slot) void {
        if (dragging.* == .empty) {
            if (self.* == .empty) return;
            // take half

            const half = self.filled.count / 2;
            self.remove(half);
            _ = dragging.give(self.filled.item, half);
        } else {
            // deposit one
            const drag = &dragging.filled;

            if (self.* == .empty or (self.filled.item.eqlType(drag.item) and self.filled.count < self.filled.item.maxStack())) {
                dragging.remove(1 - self.give(drag.item, 1));
            }
        }
    }

    pub fn draw(self: Slot, rect: rl.Rectangle, backing_color: rl.Color) void {
        const transparent_color: rl.Color = .{
            .r = backing_color.r,
            .g = backing_color.g,
            .b = backing_color.b,
            .a = @intFromFloat(@as(f32, @floatFromInt(backing_color.a)) * 0.6),
        };

        rl.DrawRectangleRec(rect, transparent_color);
        rl.DrawRectangleLinesEx(rect, 3, backing_color);

        if (self == .empty) return;

        if (self.filled.count == 0) {
            rl.DrawRectangleV(zrl.vec2(rect.x, rect.y), zrl.vec2splat(10), rl.RED);
            return;
        }

        switch (self.filled.item) {
            .block => |b| {
                const model_type = b.get(.model_type);

                switch (model_type) {
                    .block => {
                        const padding = 2;

                        Block.drawPreview(b, .{
                            .x = rect.x + padding,
                            .y = rect.y + padding,
                            .width = hotbar_item_size - padding * 2,
                            .height = hotbar_item_size - padding * 2,
                        });
                    },
                    .model => {},
                }

                var buf: [8]u8 = undefined;
                const str = std.fmt.bufPrintZ(&buf, "{}", .{self.filled.count}) catch unreachable; // count is u8, max length of u8 is 3
                rl.DrawText(str, @intFromFloat(rect.x + 2), @intFromFloat(rect.y + rect.height - 12), 10, rl.WHITE);
            },
            .tool => |t| {
                const tex_indexes = t.get(.inventory_sprite_idx);

                rl.DrawTexturePro(Tool.sprite_atlas, .{
                    .x = @floatFromInt(tex_indexes[0] * Tool.inventory_sprite_size),
                    .y = @floatFromInt(tex_indexes[1] * Tool.inventory_sprite_size),
                    .width = Tool.inventory_sprite_size,
                    .height = Tool.inventory_sprite_size,
                }, .{
                    .x = rect.x + 9,
                    .y = rect.y + 9,
                    .width = 32,
                    .height = 32,
                }, .{}, 0, rl.WHITE);

                if (t.durability < t.get(.max_durability)) {
                    rl.DrawRectangleRec(.{
                        .x = rect.x + 4,
                        .y = rect.y + rect.height - 8,
                        .width = (rect.width - 8) * t.durabilityPercent(),
                        .height = 4,
                    }, rl.GREEN);
                }
            },
            .misc => |m| {
                const tex_indexes = m.get(.inventory_sprite_idx);

                rl.DrawTexturePro(Item.Misc.sprite_atlas, .{
                    .x = @floatFromInt(tex_indexes[0] * Item.Misc.inventory_sprite_size),
                    .y = @floatFromInt(tex_indexes[1] * Item.Misc.inventory_sprite_size),
                    .width = Item.Misc.inventory_sprite_size,
                    .height = Item.Misc.inventory_sprite_size,
                }, .{
                    .x = rect.x + 9,
                    .y = rect.y + 9,
                    .width = 32,
                    .height = 32,
                }, .{}, 0, rl.WHITE);

                var buf: [8]u8 = undefined;
                const str = std.fmt.bufPrintZ(&buf, "{}", .{self.filled.count}) catch unreachable; // count is u8, max length of u8 is 3
                rl.DrawText(str, @intFromFloat(rect.x + 2), @intFromFloat(rect.y + rect.height - 12), 10, rl.WHITE);
            },
        }
    }

    pub fn updateGrid(
        slots: []Slot,
        input: c.Input,
        dragging_slot: *Slot,
        width: usize,
        pos: ztg.Vec2,
        ms_pos: rl.Vector2,
        shift_click_slots: []Slot,
    ) bool {
        if (input.isPressed(0, .gui_press) or input.isPressed(0, .gui_alt_press)) for (slots, 0..) |*slot, i| {
            if (rl.CheckCollisionPointRec(ms_pos, Slot.gridRect(pos, i, width))) {
                slot.interact(input, dragging_slot, shift_click_slots);
                return true;
            }
        };
        return false;
    }

    pub fn drawGrid(slots: []const Slot, pos: ztg.Vec2, width: usize) void {
        for (slots, 0..) |s, i| {
            const rect = gridRect(pos, i, width);
            s.draw(rect, rl.LIGHTGRAY);
        }
    }

    pub fn gridRect(start_pos: ztg.Vec2, i: usize, width: usize) rl.Rectangle {
        return .{
            .x = start_pos.x + @as(f32, @floatFromInt((i % width) * hotbar_item_size)),
            .y = start_pos.y + @as(f32, @floatFromInt((i / width) * hotbar_item_size)),
            .width = hotbar_item_size,
            .height = hotbar_item_size,
        };
    }

    pub inline fn singleRect(start_pos: ztg.Vec2) rl.Rectangle {
        return gridRect(start_pos, 0, 1);
    }

    pub fn giveAll(slots: []Slot, item: Item, quantity: u8) u8 {
        var remaining = quantity;
        var slot: *Slot = undefined;
        while (remaining > 0) {
            slot = Slot.slotFor(slots, item) orelse break;
            remaining = slot.give(item, remaining);
        }

        return remaining;
    }

    pub fn slotFor(slots: []Slot, item: Item) ?*Slot {
        for (slots) |*slot| {
            if (slot.* == .filled and slot.filled.item.eqlType(item) and slot.filled.count < item.maxStack()) return slot;
        }
        for (slots) |*slot| {
            if (slot.* == .empty) return slot;
        }
        return null;
    }

    pub fn format(value: Slot, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .empty => try writer.writeAll("empty"),
            .filled => |filled| try writer.print("filled({}, {})", .{ filled.item, filled.count }),
        }
    }
};

/// finds a slot for item, and returns how many are left over
pub fn giveItem(self: *Inventory, item: Item, quantity: u8) u8 {
    const slot = self.slotFor(item) orelse return quantity;
    return slot.give(item, quantity);
}

pub fn slotFor(self: *Inventory, item: Item) ?*Slot {
    return Slot.slotFor(
        self.slots[hotbar_offset..],
        item,
    ) orelse Slot.slotFor(
        self.slots[0..hotbar_offset],
        item,
    );
}

pub fn giveAll(self: *Inventory, com: ztg.Commands, overflow_pos: ztg.Vec3, item: Item, quantity: u8) !void {
    var remaining = quantity;
    var slot: *Slot = undefined;
    while (remaining > 0) {
        slot = self.slotFor(item) orelse break;
        remaining = slot.give(item, remaining);
    }

    _ = try ItemPickup.spawn(com, overflow_pos, .{}, remaining, item);
}

pub fn update(self: *Inventory, pos: ztg.Vec2, input: c.Input, ms_pos: rl.Vector2) void {
    _ = Slot.updateGrid(
        self.slots[0..hotbar_offset],
        input,
        &self.dragging_slot,
        inventory_width,
        pos,
        ms_pos,
        self.slots[hotbar_offset..],
    );
    _ = Slot.updateGrid(
        self.slots[hotbar_offset..],
        input,
        &self.dragging_slot,
        inventory_width,
        pos.add(.{ .y = hotbar_item_size * 3 + 10 }),
        ms_pos,
        self.slots[0..hotbar_offset],
    );
}

pub fn updateMiniCrafter(self: *Inventory, pos: ztg.Vec2, input: c.Input, ms_pos: rl.Vector2) void {
    const minicrafter_pos = pos.add(.{ .x = crafting_slots_offset });

    _ = Slot.updateGrid(
        &self.crafting_slots,
        input,
        &self.dragging_slot,
        2,
        minicrafter_pos,
        ms_pos,
        &self.slots,
    );

    if (input.isPressed(0, .gui_press)) {
        self.crafting_output.leftClick(input, self, &self.dragging_slot, &self.crafting_slots, minicrafter_pos.add(.{ .x = hotbar_item_size * 3 }), ms_pos);
    }
    if (input.isPressed(0, .gui_press) or input.isPressed(0, .gui_alt_press)) {
        self.crafting_output = .{ .slot = recipes.match(&self.crafting_slots, 2) };
    }
}

pub fn drawOpen(self: Inventory, pos: ztg.Vec2) void {
    for (self.slots, 0..) |slot, i| {
        const start_pos = if (i >= hotbar_offset) pos.add(.{ .y = 10 }) else pos;
        const rect = Slot.gridRect(start_pos, i, inventory_width);
        slot.draw(rect, rl.LIGHTGRAY);
    }

    const ms_pos = rl.GetMousePosition();
    self.dragging_slot.draw(zrl.rectangle(
        ms_pos.x,
        ms_pos.y,
        hotbar_item_size,
        hotbar_item_size,
    ), rl.BLANK);
}

pub fn drawMiniCrafter(self: Inventory, pos: ztg.Vec2) void {
    for (self.crafting_slots, 0..) |slot, i| {
        const rect = Slot.gridRect(pos.add(.{ .x = crafting_slots_offset }), i, 2);
        slot.draw(rect, rl.LIGHTGRAY);
    }

    {
        const rect = Slot.gridRect(pos.add(.{ .x = crafting_slots_offset + hotbar_item_size * 3 }), 0, 2);
        self.crafting_output.slot.draw(rect, rl.LIGHTGRAY);
    }
}

pub fn drawHotbar(self: Inventory, start_pos: ztg.Vec2, selected_slot: u8) void {
    for (hotbar_offset..len) |i| {
        const slot = &self.slots[i];
        const rect = Slot.gridRect(start_pos, i - hotbar_offset, inventory_width);
        slot.draw(
            rect,
            if (selected_slot == i - hotbar_offset)
                rl.LIGHTGRAY
            else
                rl.GRAY,
        );
    }
}

pub fn close(self: *Inventory, player_pos: ztg.Vec3, com: ztg.Commands) !void {
    if (self.dragging_slot == .filled) {
        const remaining = self.giveItem(self.dragging_slot.filled.item, self.dragging_slot.filled.count);
        _ = try ItemPickup.spawn(com, player_pos, .{}, remaining, self.dragging_slot.filled.item);
        self.dragging_slot = .empty;
    }

    for (&self.crafting_slots) |*slot| {
        if (slot.* == .filled) {
            const remaining = self.giveItem(slot.filled.item, slot.filled.count);
            _ = try ItemPickup.spawn(com, player_pos, .{}, remaining, slot.filled.item);
            slot.* = .empty;
        }
    }
}
