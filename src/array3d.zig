const std = @import("std");
const assert = @import("std").debug.assert;

pub fn Array3d(comptime _x_len: comptime_int, comptime _y_len: comptime_int, comptime _z_len: comptime_int, comptime T: type) type {
    return struct {
        pub const x_len = _x_len;
        pub const y_len = _y_len;
        pub const z_len = _z_len;

        pub const items_len = x_len * y_len * z_len;

        items: [items_len]T,

        pub fn filled(item: T) @This() {
            return .{ .items = [_]T{item} ** items_len };
        }

        pub fn xSlice(self: *@This(), y: usize, z: usize, x_begin: usize, len: usize) []T {
            assert(x_begin + len <= x_len);
            return self.items[index(x_begin, y, z)..][0..len];
        }

        pub fn xySlice(self: *@This(), z: usize, y_offset: usize, rows: usize) []T {
            assert(rows <= y_len);
            return self.items[index(0, y_offset, z)..][0 .. rows * x_len];
        }

        pub fn xySliceFull(self: *@This(), z: usize) *[x_len * y_len]T {
            return self.items[index(0, 0, z)..][0 .. x_len * y_len];
        }

        pub fn index(x: usize, y: usize, z: usize) usize {
            assertInRange(x, y, z);
            return x + y * x_len + z * x_len * y_len;
        }

        pub fn position(idx: usize) struct { usize, usize, usize } {
            return .{ idx % x_len, (idx / x_len) % y_len, idx / (x_len * y_len) };
        }

        pub fn get(self: *const @This(), x: usize, y: usize, z: usize) T {
            return @as(*const T, @ptrCast(@as([*]const T, &self.items) + index(x, y, z))).*;
        }

        pub fn getPtr(self: *@This(), x: usize, y: usize, z: usize) *T {
            return @ptrCast(@as([*]T, &self.items) + index(x, y, z));
        }

        pub fn set(self: *@This(), x: usize, y: usize, z: usize, value: T) void {
            self.items[index(x, y, z)] = value;
        }

        pub inline fn assertInRange(x: usize, y: usize, z: usize) void {
            assert(x < x_len);
            assert(y < y_len);
            assert(z < z_len);
        }
    };
}
