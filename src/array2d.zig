const assert = @import("std").debug.assert;

pub fn Array2d(comptime _x_len: comptime_int, comptime _y_len: comptime_int, comptime T: type) type {
    return struct {
        pub const x_len = _x_len;
        pub const y_len = _y_len;

        pub const items_len = x_len * y_len;

        items: [items_len]T,

        pub fn filled(item: T) @This() {
            return .{ .items = [_]T{item} ** items_len };
        }

        pub fn xSlice(self: *@This(), y: usize, x_begin: usize, len: usize) []T {
            const idx = index(x_begin, y);
            assert(x_begin + len <= x_len);
            return self.items[idx..][0..len];
        }

        pub fn xySlice(self: *@This(), y_offset: usize, rows: usize) []T {
            const start = index(0, y_offset);
            assert(rows <= y_len);
            return self.items[start..][0 .. rows * x_len];
        }

        pub fn index(x: usize, y: usize) usize {
            assertInRange(x, y);
            return x + y * x_len;
        }

        pub fn position(idx: usize) struct { usize, usize } {
            return .{ idx % x_len, (idx / x_len) % y_len };
        }

        pub fn get(self: *const @This(), x: usize, y: usize) T {
            return @as(*const T, @ptrCast(@as([*]const T, &self.items) + index(x, y))).*;
        }

        pub fn getPtr(self: *@This(), x: usize, y: usize) *T {
            return @ptrCast(@as([*]T, &self.items) + index(x, y));
        }

        pub fn set(self: *@This(), x: usize, y: usize, value: T) void {
            self.items[index(x, y)] = value;
        }

        pub inline fn assertInRange(x: usize, y: usize) void {
            assert(x < x_len);
            assert(y < y_len);
        }
    };
}
