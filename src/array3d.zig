pub fn Array3d(comptime _x_len: comptime_int, comptime _y_len: comptime_int, comptime _z_len: comptime_int, comptime T: type) type {
    return struct {
        pub const x_len = _x_len;
        pub const y_len = _y_len;
        pub const z_len = _z_len;

        pub const items_len = x_len * y_len * z_len;

        items: [items_len]T,

        pub inline fn filled(item: T) @This() {
            return .{ .items = [_]T{item} ** items_len };
        }

        pub inline fn index(x: usize, y: usize, z: usize) usize {
            return x + y * x_len + z * x_len * y_len;
        }

        pub inline fn position(idx: usize) struct { usize, usize, usize } {
            return .{ idx % x_len, (idx / x_len) % y_len, idx / (x_len * y_len) };
        }

        pub inline fn get(self: *const @This(), x: usize, y: usize, z: usize) T {
            return @as(*const T, @ptrCast(@as([*]const T, &self.items) + index(x, y, z))).*;
        }

        pub inline fn getPtr(self: *@This(), x: usize, y: usize, z: usize) *T {
            return @ptrCast(@as([*]T, &self.items) + index(x, y, z));
        }

        pub inline fn set(self: *@This(), x: usize, y: usize, z: usize, value: T) void {
            self.items[index(x, y, z)] = value;
        }
    };
}
