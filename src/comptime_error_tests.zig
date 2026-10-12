const std = @import("std");
const ecs = @import("zflecs.zig");
const builtin = @import("builtin");

const print = std.log.info;

const Position = struct { x: f32, y: f32 };
const Velocity = struct { x: f32, y: f32 };

const Apples = struct {};

fn move_apples_system(positions: []Position, velocities: []const Velocity, _: []const Apples) void {
    for (positions, velocities) |*p, v| {
        p.x += v.x;
        p.y += v.y;
    }
}

test "zflecs.block_tags_systemcomptime" {
    print("\n", .{});

    const world = ecs.init();
    defer _ = ecs.fini(world);

    ecs.COMPONENT(world, Position);
    ecs.COMPONENT(world, Velocity);

    ecs.TAG(world, Apples);

    _ = ecs.ADD_SYSTEM(world, "move system", ecs.OnUpdate, move_apples_system);
}
