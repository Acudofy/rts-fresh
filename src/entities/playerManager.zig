// castleHandler.zig
const std = @import("std");
const rl = @cImport(@cInclude("raylib.h"));

const Driver = @import("driver.zig").Driver;
const Castle = @import("castle.zig").Castle;
const MN = @import("../globals.zig");
const math = @import("../math.zig");

const RenderManager = @import("../world/renderManager.zig").RenderManager;
const EntityManager = @import("entityManager.zig").EntityManager;

// Types
const entityPtr = @import("entityManager.zig").entityPtr;

pub const PlayerManager = struct {
    id: MN.Player,
    driver: Driver,
    renderer: *RenderManager,
    entityManager: *EntityManager,
    selected: c_int = 0,

    _lastMouseClickPos: rl.Vector2 = undefined,
    _dragSelectBox: bool = false,
    _selectBox: rl.Rectangle = undefined,

    // entityCounter: *usize,
    // selectedEntities: [255]EntityUnion = undefined,
    // selectedEntitiesAmount: usize = 0,
    debugvar: usize = undefined,
    //castle_is_selected: bool,

    pub fn init(Renderer: *RenderManager, entityManager: *EntityManager, id: MN.Player) PlayerManager {
        return PlayerManager{
            .id = id,
            .entityManager = entityManager,
            .driver = Driver.init(),
            .renderer = Renderer,
        };
    }

    pub fn update(self: *PlayerManager) void {
        // const driver_pos = self.driver.getPosition();
        // const castle_pos = self.movingCastle.getPosition();
        // const proximity_threshold = self.movingCastle.getProximityThreshold();


        // Check actions
        // if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_RIGHT)) {
        //     std.debug.print("Bitchboi UwU", .{});
        //     // self.checkSelection(camera);
        // }

        self.spawnCastle(rl.KEY_R);

        self.mouseSelect(rl.MOUSE_BUTTON_LEFT); // Make selection
        self.moveSelection(rl.MOUSE_BUTTON_RIGHT);
        // if (self.selected > 0){
        //     std.debug.print("selected {} entities \n", .{self.selected});
        // }

        // const distance_to_castle = std.math.sqrt(
        //     (driver_pos.x - castle_pos.x) * (driver_pos.x - castle_pos.x) +
        //         (driver_pos.z - castle_pos.z) * (driver_pos.z - castle_pos.z),
        // );

        // if (!self.driver.isInsideCastle()) {
        //     self.driver.update(camera, delta_time); // Update Driver independently when outside

        //     // Check for proximity and space key press to enter
        //     if (distance_to_castle < proximity_threshold and rl.IsKeyPressed(rl.KEY_SPACE)) {
        //         self.enterCastle();
        //     }
        // } else {
        //     // User is inside the castle
        //     self.syncDriverPositionWithCastle();

        //     // Check for space key press to exit
        //     if (rl.IsKeyPressed(rl.KEY_SPACE)) {
        //         self.exitCastle();
        //     }
        // }
    }

    pub fn mouseSelect(self: *PlayerManager, keypress: c_int) void {
        if(rl.IsMouseButtonPressed(keypress)){ // key rising edge
            self._lastMouseClickPos = rl.GetMousePosition();
        }

        if(rl.IsMouseButtonDown(keypress)){ // If mouse is down
            if (!self._dragSelectBox){ // if mouse not out of deadzone
                if(math.vectorDistanceSquared(rl.GetMousePosition(), self._lastMouseClickPos) > MN.MOUSE_DEADZONE){ // If mouse moves outside of deadzone
                    self._dragSelectBox = true;
                    self._selectBox = math.createRect(self._lastMouseClickPos, rl.GetMousePosition());

                }
            } else{ // if mouse is out of deadzone
                self._selectBox = math.createRect(self._lastMouseClickPos, rl.GetMousePosition());
            }
        }
        if(rl.IsMouseButtonReleased(keypress)){
            if (self._dragSelectBox) {
                // self._selectBox = math.createRect(self._lastMouseClickPos, rl.GetMousePosition());
                self.selected += self.entityManager.selectWithin(self._selectBox, self.id) catch 0; // return 0 if selection could not be completed due to lack of memory
                self._dragSelectBox = false;
            } else {
                const mouseray = rl.GetScreenToWorldRay(rl.GetMousePosition(), self.renderer.camera.*);
                const selectChange = self.entityManager.selectWithRay(mouseray, self.id);
                if (selectChange != 0){
                    self.selected += selectChange;
                } else {
                    self.entityManager.deselectAll(self.id);
                    self.selected = 0;
                }
            }
            std.debug.print("selected entities: {}\n", .{self.selected});
        }
    }

    fn spawnCastle(self: *PlayerManager, keypress: c_int) void {
        if (rl.IsKeyReleased(keypress)){ // If key is pressed
            const spawnloc: rl.Vector3 = self.getMouseMapPosition(); // Get spawn location
            self.entityManager.spawnCastle(spawnloc, self.id) catch |err| {
                std.debug.print("Error spawning castle: {}\n", .{err});
            };
        }
    }

    fn moveSelection(self: *PlayerManager, keypress: c_int) void {
        if (rl.IsMouseButtonReleased(keypress)){
            self.entityManager.moveSelection(self.getMouseMapPosition(), self.id);
            self.selected = 0;
        }
    }

    pub fn draw(self: PlayerManager) void {
        self.entityManager.draw();
    }

    pub fn draw2D(self: PlayerManager) void {
        if (self._dragSelectBox) {
            rl.DrawRectangleLinesEx(self._selectBox, 2.0, rl.GREEN);
        }
    }

    pub fn getMouseMapPosition(self: *PlayerManager) rl.Vector3 {
        // Returns point on map which has been hit by ray, if nothing was hit return (0,0,0)
        const renderer = self.renderer;
        const mouseray = rl.GetScreenToWorldRay(rl.GetMousePosition(), renderer.camera.*);
        var colision:rl.RayCollision = undefined;
        var i:usize = 0;
        while(i < MN.N_CHUNKS):(i+=1){
            colision = rl.GetRayCollisionBox(mouseray, renderer.map.boundingBoxes[i]);
            if (colision.hit){
                const transformation = renderer.map.transforms[i];
                colision = rl.GetRayCollisionMesh(mouseray, renderer.map.meshes[i], transformation);                       // Get collision info between ray and mesh
                if (colision.hit){
                    return colision.point;
                }
            }
        }
        return rl.Vector3{.x = 0, .y = 0, .z = 0};
    }

    // fn draw3dlineOnScreen(self: PlayerManager, rec: rl.Rectangle) void {

    // }

    // fn enterCastle(self: *PlayerManager) void {
    //     const castle_pos = self.movingCastle.getPosition();
    //     self.driver.setInsideCastle(true);
    //     self.driver.setPosition(castle_pos); // Position driver inside the castle
    // }

    // fn exitCastle(self: *PlayerManager) void {
    //     const castle_pos = self.movingCastle.getPosition();
    //     const castle_dims = self.movingCastle.getDimensions();
    //     const driver_dims = self.driver.dimensions;

    //     self.driver.setInsideCastle(false);
    //     self.driver.setPosition(rl.Vector3{
    //         .x = castle_pos.x + castle_dims.x / 2.0 + driver_dims.x / 2.0 + 0.1, // Position driver outside, next to the castle, adding a small gap
    //         .y = castle_pos.y,
    //         .z = castle_pos.z,
    //     });
    // }

    // pub fn checkSelection(self: *PlayerManager, camera: rl.Camera3D) void {
    //     const mouse_pos = rl.GetMousePosition();
    //     const castle_pos = rl.GetWorldToScreen(self.movingCastle.getPosition(), camera);

    //     const distance_x = @abs(mouse_pos.x - castle_pos.x);
    //     const distance_y = @abs(mouse_pos.y - castle_pos.y);

    //     if (distance_x < 100 and distance_y < 100) {
    //         self.movingCastle.selected = true;
    //     }
    //     std.debug.print("klik {}", .{self.movingCastle.selected});
    // }

    // fn syncDriverPositionWithCastle(self: *PlayerManager) void {
    //     const castle_pos = self.movingCastle.getPosition();
    //     self.driver.setPosition(castle_pos); // Keep driver position synced with the castle while inside
    // }
};

// TODO: Add get position on map from mouse function
// TODO: Action check section in update function
// TODO: Spawn castle with unique ID 