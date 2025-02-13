// Import libraries
const std = @import("std");
const rl = @cImport(@cInclude("raylib.h"));

// Import dependency structs
const MN = @import("globals.zig");
const math = @import("math.zig");

const CameraController = @import("world/cameraController.zig").CameraController;
const RenderManager= @import("world/renderManager.zig").RenderManager;
const EntityManager = @import("entities/entityManager.zig").EntityManager;
const PlayerManager = @import("entities/playerManager.zig").PlayerManager;

// Main loop
pub fn main() !void {

    // ==== Creating an Allocator ====
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();


    // ==== Setup window ====
    rl.InitWindow(MN.SCREEN_WIDTH, MN.SCREEN_HEIGHT, "Mastle POC");
    defer rl.CloseWindow();
    rl.SetTargetFPS(MN.SCREEN_FPS);


    // ==== Initialize entities and camera ====
    var camera_controller = CameraController.init(.{});
    
    // render_manager = Render
    var render_manager = try RenderManager.init(allocator, MN.MAP_HEIGHT, MN.MAP_WIDTH, MN.MAP_HEIGHT_Z, MN.HM_LOCATION, MN.X_CHUNKS, MN.Y_CHUNKS, &camera_controller.camera);
    defer render_manager.deinit();

    var entityManager = try EntityManager.init(allocator, &render_manager, 2);
    defer entityManager.deinit();
    var player_manager = PlayerManager.init(&render_manager, &entityManager, MN.Player.PLAYER1);
    

    // ==== Setup Game ====
    // render_manager.setDebugMode(true);

    // ==== Game loop ====
    while (!rl.WindowShouldClose()) {
        // ==== Update variables ====
        const deltaTime = rl.GetFrameTime();

        camera_controller.update();
        camera_controller.handleZoom();
        
        player_manager.update();
        
        entityManager.update(deltaTime);

        render_manager.update();

        // ==== Draw frame ====
        rl.BeginDrawing();
            rl.ClearBackground(rl.WHITE);
            rl.BeginMode3D(camera_controller.camera);

                rl.DrawGrid(25, 1.0);

                render_manager.draw();
                player_manager.draw();

            rl.EndMode3D();
            
            player_manager.draw2D();
        rl.EndDrawing();
    }
}
