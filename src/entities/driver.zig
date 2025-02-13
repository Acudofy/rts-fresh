// driver.zig
const std = @import("std");
const rl = @cImport(@cInclude("raylib.h"));
const m = @import("../math.zig");

pub const Driver = struct {
    position: rl.Vector3,
    dimensions: rl.Vector3,
    speed: f32,
    inside_castle: bool,
    color: rl.Color,

    pub fn init() Driver {
        return Driver{
            .position = rl.Vector3{ .x = 5, .y = 0, .z = 5 },
            .dimensions = rl.Vector3{ .x = 0.5, .y = 0.5, .z = 0.5 },
            .speed = 7.5,
            .inside_castle = false, // Player starts outside
            .color = rl.BLUE,
        };
    }

    pub fn draw(self: Driver) void {
        rl.DrawCube(self.position, self.dimensions.x, self.dimensions.y, self.dimensions.z, self.color);
    }

    pub fn update(self: *Driver, camera: rl.Camera3D, delta_time: f32) void {
        if (!self.inside_castle) {
            self.moveRelativeCamera(camera, delta_time);
        }
    }

    fn moveRelativeCamera(self: *Driver, camera: rl.Camera3D, delta_time: f32) void {
        var forward_vector = m.vector3Subtract(camera.target, camera.position);
        forward_vector = m.vector3Normalize(forward_vector);

        var right_vector = m.vector3CrossProduct(forward_vector, camera.up);
        right_vector = m.vector3Normalize(right_vector);

        // Project forward and right vectors onto the XZ plane (y = 0)
        forward_vector.y = 0;
        forward_vector = m.vector3Normalize(forward_vector);

        right_vector.y = 0;
        right_vector = m.vector3Normalize(right_vector);

        if (rl.IsKeyDown(rl.KEY_D)) { // Right relative to camera
            self.position.x += right_vector.x * self.speed * delta_time;
            self.position.z += right_vector.z * self.speed * delta_time;
        }
        if (rl.IsKeyDown(rl.KEY_A)) { // Left relative to camera
            self.position.x -= right_vector.x * self.speed * delta_time;
            self.position.z -= right_vector.z * self.speed * delta_time;
        }
        if (rl.IsKeyDown(rl.KEY_W)) { // Forward relative to camera
            self.position.x += forward_vector.x * self.speed * delta_time;
            self.position.z += forward_vector.z * self.speed * delta_time;
        }
        if (rl.IsKeyDown(rl.KEY_S)) { // Backward relative to camera
            self.position.x -= forward_vector.x * self.speed * delta_time;
            self.position.z -= forward_vector.z * self.speed * delta_time;
        }
    }

    pub fn setPosition(self: *Driver, position: rl.Vector3) void {
        self.position = position;
    }

    pub fn getPosition(self: Driver) rl.Vector3 {
        return self.position;
    }

    pub fn setInsideCastle(self: *Driver, inside: bool) void {
        self.inside_castle = inside;
    }

    pub fn isInsideCastle(self: Driver) bool {
        return self.inside_castle;
    }
};
