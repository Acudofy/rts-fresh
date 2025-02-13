const std = @import("std");
const rl = @cImport(@cInclude("raylib.h"));
const MN = @import("../globals.zig"); // Assuming this is still relevant

pub const CameraConfig = struct {
    // Isometric angle configurations
    iso_angle: f32 = 135.0, // Rotation around Y axis (degrees)
    iso_pitch: f32 = 30.0, // Angle from horizontal plane (degrees)
    distance: f32 = 20.0, // Distance from target

    // Initial camera target position (world coordinates)
    target_position: rl.Vector3 = rl.Vector3{ .x = 0, .y = 0, .z = 0 },

    fov: f32 = 45, // Field of View (degrees)

    // Screen border for camera movement activation
    border_size: f32 = 75,
    // Camera movement parameters
    acceleration: f32 = 0.2,
    max_speed: f32 = 0.5,
    friction: f32 = 0.5,
    movement_smoothing: f32 = 0.07,
};

pub const CameraController = struct {
    camera: rl.Camera3D,
    velocity: rl.Vector2, // Use Vector2 for velocity (x and z plane movement)
    config: CameraConfig,

    pub fn init(config: CameraConfig) CameraController {
        var camera = CameraController{
            .camera = rl.Camera3D{
                .position = rl.Vector3{ .x = 0, .y = 0, .z = 0 },
                .target = config.target_position,
                .up = rl.Vector3{ .x = 0, .y = 1, .z = 0 },
                .fovy = config.fov,
                .projection = rl.CAMERA_PERSPECTIVE,
            },
            .velocity = rl.Vector2{ .x = 0, .y = 0 }, // Initialize velocity as Vector2
            .config = config,
        };
        camera.updateIsometricPosition();
        return camera;
    }

    // Updates camera position to maintain isometric view based on current target and config
    fn updateIsometricPosition(self: *CameraController) void {
        const angle_rad = self.config.iso_angle * std.math.pi / 180.0;
        const pitch_rad = self.config.iso_pitch * std.math.pi / 180.0;

        // Calculate camera position based on spherical coordinates relative to target
        self.camera.position.x = self.camera.target.x +
            self.config.distance * @cos(pitch_rad) * @cos(angle_rad);
        self.camera.position.y = self.camera.target.y +
            self.config.distance * @sin(pitch_rad);
        self.camera.position.z = self.camera.target.z +
            self.config.distance * @cos(pitch_rad) * @sin(angle_rad);
    }

    // Calculates velocity component based on mouse position relative to screen borders
    fn calculateVelocity(self: *CameraController, current_velocity: f32, position: f32, border: f32) f32 {
        const border_size = self.config.border_size;
        const acceleration = self.config.acceleration;
        const max_speed = self.config.max_speed;
        const friction = self.config.friction;

        const encroach: f32 =   if (position >= border - border_size) @min((position - (border - border_size))/border_size, 1) // Right border encroachment (between 0-1)
                                else if (position <= border_size) @max((position - border_size)/border_size, -1) // left border encroachment
                                else 0; // No encroachment
        

        const vel_new = if (encroach > 0) @min(current_velocity + acceleration*std.math.pow(f32, encroach, 3) - friction*current_velocity/max_speed, max_speed) // Calculate new velocity & limit by max_speed
                        else @max(current_velocity + acceleration*std.math.pow(f32, encroach, 3) - friction*current_velocity/max_speed, -max_speed);

        return vel_new;
    }

    pub fn update(self: *CameraController) void {
        const mouse_position = rl.GetMousePosition();
        const screen_width: f32 = @floatFromInt(rl.GetScreenWidth());
        const screen_height: f32 = @floatFromInt(rl.GetScreenHeight());

        // Calculate target velocities for X and Z axes based on mouse position
        const target_velocity_x = self.calculateVelocity(self.velocity.x, mouse_position.x, screen_width);
        const target_velocity_z = self.calculateVelocity(self.velocity.y, mouse_position.y, screen_height); // Use velocity.y for Z

        // Smooth velocity transitions
        const movement_smoothing = self.config.movement_smoothing;
        self.velocity.x += (target_velocity_x - self.velocity.x) * movement_smoothing;
        self.velocity.y += (target_velocity_z - self.velocity.y) * movement_smoothing; // Update velocity.y

        // Convert screen-space velocity to world-space movement based on isometric angle
        const angle_rad = self.config.iso_angle * std.math.pi / 180.0;
        const movement_x = self.velocity.x * @sin(angle_rad) + self.velocity.y * @cos(angle_rad); // Use velocity.y
        const movement_z = -self.velocity.x * @cos(angle_rad) + self.velocity.y * @sin(angle_rad); // Use velocity.y

        // Apply movement to camera target, clamped within world bounds
        const world_bounds = struct {
            const min_x: f32 = -100;
            const max_x: f32 = 100;
            const min_z: f32 = -100;
            const max_z: f32 = 100;
        };

        var new_target = self.camera.target; // Create a mutable copy
        new_target.x += movement_x;
        new_target.z += movement_z;

        // Clamp target position within world bounds
        new_target.x = std.math.clamp(new_target.x, world_bounds.min_x, world_bounds.max_x);
        new_target.z = std.math.clamp(new_target.z, world_bounds.min_z, world_bounds.max_z);
        self.camera.target = new_target; // Update camera target

        // Update camera position based on the (potentially clamped) target
        self.updateIsometricPosition();
    }

    pub fn handleZoom(self: *CameraController) void {
        const wheel_move = rl.GetMouseWheelMove();
        if (wheel_move != 0) {
            const zoom_speed: f32 = 2;
            const min_distance: f32 = 5.0;
            const max_distance: f32 = 1000.0;

            // Update distance while maintaining isometric angle
            const new_distance = self.config.distance - (wheel_move * zoom_speed);
            if (new_distance >= min_distance and new_distance <= max_distance) {
                self.config.distance = new_distance;
                self.updateIsometricPosition();
            }
        }
    }

    pub fn getCamera(self: CameraController) rl.Camera3D { // Added getter for the camera itself if needed
        return self.camera;
    }
};
