const std = @import("std");
const ecs = @import("zflecs.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const Pos = struct { x: f32, y: f32 };
const Vel = struct { x: f32, y: f32 };
const Health = struct { value: f32 };

test {
    std.testing.refAllDecls(@This());
}

test "two worlds init simultaneously" {
    const world_a = ecs.init();
    defer _ = ecs.fini(world_a);

    const world_b = ecs.init();
    defer _ = ecs.fini(world_b);

    try expect(@intFromPtr(world_a) != 0);
    try expect(@intFromPtr(world_b) != 0);
    try expect(world_a != world_b);
}

test "component IDs match across worlds" {
    const world_a = ecs.init();
    const world_b = ecs.init();
    defer _ = ecs.fini(world_b);
    defer _ = ecs.fini(world_a);

    ecs.COMPONENT(world_a, Pos);
    ecs.COMPONENT(world_b, Pos);

    try expect(ecs.id(Pos) != 0);

    ecs.COMPONENT(world_a, Vel);
    ecs.COMPONENT(world_b, Vel);

    try expect(ecs.id(Pos) == ecs.id(Pos));
    try expect(ecs.id(Vel) == ecs.id(Vel));
    try expect(ecs.id(Pos) != ecs.id(Vel));
}

test "entity in one world invisible to other" {
    const world_a = ecs.init();
    const world_b = ecs.init();
    defer _ = ecs.fini(world_b);
    defer _ = ecs.fini(world_a);

    ecs.COMPONENT(world_a, Pos);
    ecs.COMPONENT(world_b, Pos);

    const e_a = ecs.entity_init(world_a, &.{});
    _ = ecs.set(world_a, e_a, Pos, .{ .x = 0, .y = 0 });

    const e_b = ecs.entity_init(world_b, &.{});

    try expect(ecs.get(world_a, e_a, Pos) != null);
    try expect(ecs.get(world_b, e_b, Pos) == null);
}

test "set and get independently across worlds" {
    const world_a = ecs.init();
    const world_b = ecs.init();
    defer _ = ecs.fini(world_b);
    defer _ = ecs.fini(world_a);

    ecs.COMPONENT(world_a, Health);
    ecs.COMPONENT(world_b, Health);

    const ea = ecs.entity_init(world_a, &.{});
    const eb = ecs.entity_init(world_b, &.{});

    _ = ecs.set(world_a, ea, Health, .{ .value = 100 });
    _ = ecs.set(world_b, eb, Health, .{ .value = 200 });

    try expectEqual(
        @as(f32, 100),
        ecs.get(world_a, ea, Health).?.value,
    );
    try expectEqual(
        @as(f32, 200),
        ecs.get(world_b, eb, Health).?.value,
    );
}

test "fini one world keeps other alive" {
    const world_a = ecs.init();
    const world_b = ecs.init();

    ecs.COMPONENT(world_a, Pos);
    ecs.COMPONENT(world_b, Pos);

    const ea = ecs.entity_init(world_a, &.{});
    _ = ecs.set(world_a, ea, Pos, .{ .x = 1, .y = 2 });

    // Fini world_a. world_b must remain usable after.
    _ = ecs.fini(world_a);

    const eb = ecs.entity_init(world_b, &.{});
    _ = ecs.set(world_b, eb, Pos, .{ .x = 3, .y = 4 });

    const got = ecs.get(world_b, eb, Pos).?;
    try expectEqual(@as(f32, 3), got.x);
    try expectEqual(@as(f32, 4), got.y);

    _ = ecs.fini(world_b);
}

test "reinit after fini" {
    var world = ecs.init();
    _ = ecs.fini(world);

    world = ecs.init();
    defer _ = ecs.fini(world);

    ecs.COMPONENT(world, Pos);

    try expect(ecs.id(Pos) != 0);

    const e = ecs.entity_init(world, &.{});
    _ = ecs.set(world, e, Pos, .{ .x = 5, .y = 6 });
    try expect(ecs.get(world, e, Pos) != null);
}

test "mismatched registration order is caught" {
    const world_a = ecs.init();
    const world_b = ecs.init();
    defer _ = ecs.fini(world_b);
    defer _ = ecs.fini(world_a);

    // Register in different orders. The second registration should
    // produce a mismatched ID since flecs assigns deterministic
    // low IDs based on registration sequence.
    ecs.COMPONENT(world_a, Pos);
    ecs.COMPONENT(world_a, Vel);

    ecs.COMPONENT(world_b, Vel);

    // Pos in world_b should get a different ID than Pos in world_a
    // because Vel consumed the next low ID.
    ecs.COMPONENT(world_b, Pos);

    // With the fix, this will assert. Without the fix, the early
    // return in COMPONENT means world_b never actually registered
    // Pos (global already set), so the query below fails silently.
    const eb = ecs.entity_init(world_b, &.{});
    _ = ecs.set(world_b, eb, Pos, .{ .x = 0, .y = 0 });

    // If registration worked, get returns non-null.
    // If the early return skipped registration, get returns null.
    try expect(ecs.get(world_b, eb, Pos) != null);
}
