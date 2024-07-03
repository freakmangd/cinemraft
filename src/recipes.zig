const std = @import("std");
const c = @import("init.zig");
const Block = c.Block;
const Item = c.Item;
const Inventory = c.Inventory;
const Slot = Inventory.Slot;

const Pattern = struct {
    input: []const PatternSlot,
    output: Slot,
};

const PatternSlot = union(enum) {
    item: Item,
    any: []const PatternSlot,
    empty,
    new_line,

    pub fn format(value: PatternSlot, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .item => |item| try writer.print("{}", .{item}),
            inline .empty, .new_line => |_, t| try writer.writeAll(@tagName(t)),
        }
    }
};

const patterns_container = struct {
    fn block(t: Block.Type) PatternSlot {
        return .{ .item = Item.init(.block, t) };
    }

    fn tool(t: Item.Tool.Type) PatternSlot {
        return .{ .item = Item.init(.tool, t) };
    }

    fn misc(t: Item.Misc) PatternSlot {
        return .{ .item = Item.init(.misc, t) };
    }

    fn any(items: []const PatternSlot) PatternSlot {
        return .{ .any = items };
    }

    const any_stone = any(&.{ block(.stone), block(.cobblestone) });
    const any_wood_plank = any(&.{ block(.wood_plank), block(.urple_wood_plank) });

    const _patterns = [_]Pattern{
        // W
        .{
            .input = &.{block(.wood)},
            .output = Slot.init(.block, .wood_plank, 4),
        },
        // W W
        // W W
        .{
            .input = &.{
                any_wood_plank, any_wood_plank, .new_line, //
                any_wood_plank, any_wood_plank, //
            },
            .output = Slot.init(.block, .crafting_table, 1),
        },
        // W
        // W
        .{
            .input = &.{ any_wood_plank, .new_line, any_wood_plank },
            .output = Slot.init(.misc, .stick, 4),
        },
        // W W W
        // _ S
        // _ S
        .{
            .input = &.{
                any_wood_plank, any_wood_plank, any_wood_plank, .new_line,
                .empty, misc(.stick), .new_line, //
                .empty, misc(.stick), //
            },
            .output = Slot.init(.tool, .wood_pickaxe, 1),
        },
        // W W
        // S W
        // S
        .{
            .input = &.{
                any_wood_plank, any_wood_plank, .new_line,
                misc(.stick), any_wood_plank, .new_line, //
                misc(.stick), //
            },
            .output = Slot.init(.tool, .wood_axe, 1),
        },
        // W W
        // W S
        // _ S
        .{
            .input = &.{
                any_wood_plank, any_wood_plank, .new_line,
                any_wood_plank, misc(.stick), .new_line, //
                .empty, misc(.stick), //
            },
            .output = Slot.init(.tool, .wood_axe, 1),
        },
        // W
        // S
        // S
        .{
            .input = &.{
                any_wood_plank, .new_line,
                misc(.stick), .new_line, //
                misc(.stick), //
            },
            .output = Slot.init(.tool, .wood_shovel, 1),
        },
        // C C C
        // _ S
        // _ S
        .{
            .input = &.{
                any_stone, any_stone, any_stone, .new_line,
                .empty, misc(.stick), .new_line, //
                .empty, misc(.stick), //
            },
            .output = Slot.init(.tool, .stone_pickaxe, 1),
        },
        // C C
        // S C
        // S
        .{
            .input = &.{
                any_stone, any_stone, .new_line,
                misc(.stick), any_stone, .new_line, //
                misc(.stick), //
            },
            .output = Slot.init(.tool, .stone_axe, 1),
        },
        // C C
        // C S
        // _ S
        .{
            .input = &.{
                any_stone, any_stone, .new_line,
                any_stone, misc(.stick), .new_line, //
                .empty, misc(.stick), //
            },
            .output = Slot.init(.tool, .stone_axe, 1),
        },
        // C
        // S
        // S
        .{
            .input = &.{
                any_stone, .new_line,
                misc(.stick), .new_line, //
                misc(.stick), //
            },
            .output = Slot.init(.tool, .stone_shovel, 1),
        },
        .{
            .input = &.{
                misc(.sugar), misc(.apple), misc(.sugar), .new_line, //
                misc(.wheat), misc(.wheat), misc(.wheat), //
            },
            .output = Slot.init(.block, .apple_pie, 1),
        },
        .{
            .input = &.{
                any_wood_plank, any_wood_plank, any_wood_plank, .new_line, //
                any_wood_plank, .empty, any_wood_plank, .new_line, //
                any_wood_plank, any_wood_plank, any_wood_plank, //
            },
            .output = Slot.init(.block, .chest, 1),
        },
        .{
            .input = &.{block(.urple_wood)},
            .output = Slot.init(.block, .urple_wood_plank, 4),
        },
    };
};
const patterns = patterns_container._patterns;

pub fn match(all_slots: []const Inventory.Slot, width: usize) Slot {
    //std.debug.print("\n\n\n", .{});
    //std.log.info("Searching recipes", .{});

    const upleft_most_slot, const leftmost = blk: {
        const uppermost_idx = for (all_slots, 0..) |slot, i| {
            if (slot != .empty) break i;
        } else return .empty;

        const leftmost = leftmost: {
            var leftmost = uppermost_idx % width;
            for (all_slots[uppermost_idx + 1 ..], uppermost_idx + 1..) |slot, i| {
                if (slot == .empty) continue;
                //std.log.info("leftmost? {} == {} -> {}", .{ i, i % width, slot });
                leftmost = @min(leftmost, i % width);
            }
            break :leftmost leftmost;
        };

        //std.log.info("{} {} {}", .{ uppermost_idx, (uppermost_idx / width) * width + leftmost, leftmost });
        break :blk .{ (uppermost_idx / width) * width + leftmost, leftmost };
    };
    const filled_slots = all_slots[upleft_most_slot..];

    pattern_loop: for (patterns) |pattern| {
        //std.debug.print("\n\ninfo: Checking recipe {}\n", .{pattern.output.filled.item});
        var cur_slot_check: usize = 0;

        for (pattern.input) |pat_slot| {
            if (cur_slot_check >= filled_slots.len) continue :pattern_loop;
            if (!checkSlot(upleft_most_slot, width, leftmost, filled_slots, &cur_slot_check, pat_slot)) continue :pattern_loop;
        }

        for (filled_slots[cur_slot_check..]) |other_slot| {
            if (other_slot != .empty) continue :pattern_loop;
        }

        //std.log.info("no other slot contains anything... returning {}", .{pattern.output});

        return pattern.output;
    }
    return .empty;
}

fn checkSlot(upleft_most_slot: usize, width: usize, leftmost: usize, filled_slots: []const Slot, cur_slot_check: *usize, pat_slot: PatternSlot) bool {
    const check_slot = filled_slots[cur_slot_check.*];
    //std.log.info("checking {} ({}) for {}", .{ upleft_most_slot + cur_slot_check, check_slot, block_t });

    switch (pat_slot) {
        .new_line => {
            // this is such a shitshow, but its supposed to do:
            // (_) = current
            //
            // [ ][ ](x)    [ ][ ][x]    [ ][x][x]
            // [ ][x][x] -> ( )[x][x] -> [ ][x][x]
            // [x][x][ ]    [x][x][ ]    (x)[x][ ]
            //
            // it goes to the next line down at the leftmost slot
            const global_slot = (cur_slot_check.* - 1) + upleft_most_slot;
            const desired = ((((global_slot + width) / width) * width) + leftmost) - upleft_most_slot;

            if (desired >= filled_slots.len) return false;

            for (filled_slots[cur_slot_check.*..desired]) |slot| {
                if (slot != .empty) return false;
            }

            cur_slot_check.* = desired;
        },
        .empty => {
            if (check_slot != .empty) {
                //std.log.info("Wanted empty but it wasnt!!!", .{});
                return false;
            }

            cur_slot_check.* += 1;
        },
        .item => |expected_item| {
            if (check_slot == .empty or
                !Item.eqlType(expected_item, check_slot.filled.item))
            {
                //if (check_slot != .empty) {
                //    std.log.info("Instead found {} :(", .{check_slot.filled.item});
                //}
                return false;
            }

            cur_slot_check.* += 1;
            //std.log.info("found it!", .{});
        },
        .any => |any| {
            for (any) |case| {
                if (checkSlot(upleft_most_slot, width, leftmost, filled_slots, cur_slot_check, case)) {
                    break;
                }
            } else return false;
        },
    }

    return true;
}
