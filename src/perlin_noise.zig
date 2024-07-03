// ripped from https://en.wikipedia.org/wiki/Perlin_noise
const std = @import("std");

fn interpolate(a0: f32, a1: f32, w: f32) f32 {
    // You may want clamping by inserting:
    // if (0.0 > w) return a0;
    // if (1.0 < w) return a1;
    //
    return (a1 - a0) * w + a0;
    // * // Use this cubic interpolation [[Smoothstep]] instead, for a smooth appearance:
    // * return (a1 - a0) * (3.0 - w * 2.0) * w * w + a0;
    // *
    // * // Use [[Smootherstep]] for an even smoother result with a second derivative equal to zero on boundaries:
    // * return (a1 - a0) * ((w * (w * 6.0 - 15.0) + 10.0) * w * w * w) + a0;
    // *
}

// Create pseudorandom direction vector
fn randomGradient(rand: std.rand.Random) @Vector(2, f32) {
    const theta = rand.float(f32) * std.math.tau;
    return .{ std.math.cos(theta), std.math.sin(theta) };
}

// Computes the dot product of the distance and gradient vectors.
fn dotGridGradient(rand: std.rand.Random, ix: i32, iy: i32, x: f32, y: f32) f32 {
    // Get gradient from integer coordinates
    const gradient = randomGradient(rand);

    // Compute the distance vector
    const dx: f32 = x - @as(f32, @floatFromInt(ix));
    const dy: f32 = y - @as(f32, @floatFromInt(iy));

    // Compute the dot-product
    return (dx * gradient[0] + dy * gradient[1]);
}

/// Compute Perlin noise at coordinates x, y
/// Will return in range -1 to 1.
pub fn perlin(rand: std.rand.Random, x: f32, y: f32) f32 {
    // Determine grid cell coordinates
    const x0: i32 = @intFromFloat(x);
    const x1 = x0 + 1;
    const y0: i32 = @intFromFloat(y);
    const y1 = y0 + 1;

    // Determine interpolation weights
    // Could also use higher order polynomial/s-curve here
    const sx = x - @as(f32, @floatFromInt(x0));
    const sy = y - @as(f32, @floatFromInt(y0));

    // Interpolate between grid point gradients
    const n0 = dotGridGradient(rand, x0, y0, x, y);
    const n1 = dotGridGradient(rand, x1, y0, x, y);
    const ix0 = interpolate(n0, n1, sx);

    const n2 = dotGridGradient(rand, x0, y1, x, y);
    const n3 = dotGridGradient(rand, x1, y1, x, y);
    const ix1 = interpolate(n2, n3, sx);

    return interpolate(ix0, ix1, sy);
}

pub fn perlin01(rand: std.rand.Random, x: f32, y: f32) f32 {
    return perlin(rand, x, y) * 0.5 + 0.5;
}

test perlin {
    var rng = std.rand.DefaultPrng.init(0);
    const rand = rng.random();

    for (0..10) |_x| for (0..10) |_y| {
        const x: f32 = @floatFromInt(_x);
        const y: f32 = @floatFromInt(_y);
        std.debug.print("{} {} => {d}\n", .{ x, y, perlin(rand, x * 10, y * 10) });
    };
}
