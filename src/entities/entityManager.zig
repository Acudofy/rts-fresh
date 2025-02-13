const std = @import("std");
const rl = @cImport(@cInclude("raylib.h"));

const Driver = @import("driver.zig").Driver;
const Castle = @import("castle.zig").Castle;
const MN = @import("../globals.zig");
const math = @import("../math.zig");

const RenderManager = @import("../world/renderManager.zig").RenderManager;
const PlayerManager = @import("playerManager.zig").PlayerManager;

const entityPtr: type = union(enum) {driver: *Driver, castle: *Castle};
const Allocator: type = std.mem.Allocator;

pub const EntityManager = struct{ 
    allocator: Allocator,
    renderer:  *RenderManager,

    players: usize,
    playerSelect: [][MN.MAX_ENTITIES]bool = undefined,

    entities: [MN.MAX_ENTITIES]entityPtr = undefined,
    entitycount: usize = 0,
    debugVar: struct {rl.Mesh, bool} = undefined,
    
    pub fn init(allocator: Allocator, renderer: *RenderManager, players: usize) !EntityManager {
        var entityManager: EntityManager = .{
            .allocator = allocator,
            .renderer = renderer,

            .players = players
        };

        try entityManager.initPlayerSelect(allocator, players);
        
        return entityManager;
    }

    pub fn deinit(self: *EntityManager) void {
        var i:usize = 0;
        while(i < self.entitycount):(i+=1){
            const ent: entityPtr = self.entities[i];
            switch (ent){
                .castle => | castleEntity | self.allocator.destroy(castleEntity), 
                .driver => | driverEntity | self.allocator.destroy(driverEntity),
            }
        }

        self.allocator.free(self.playerSelect);
    }

    pub fn update(self: EntityManager, deltaTime: f32) void {
        
        var i:usize = 0;
        while (i<self.entitycount):(i+=1){
            const ent: entityPtr = self.entities[i];
            
            switch (ent) 
            {
                .castle => | castleEntity | 
                {
                    castleEntity.update(deltaTime);
                },
                .driver => | driverEntity |
                {
                    std.debug.print("Missing handling of driver in update: {}\n", .{driverEntity.position});

                }
            }
        }
    }

    pub fn spawnCastle(self: *EntityManager, position: rl.Vector3, owner: MN.Player) !void {
        const castle: *Castle = try self.allocator.create(Castle); // Free memory
        
        castle.* = Castle.init(self.entitycount, position, owner, self); // Use memory to store Castle Entity
        castle.model.transform = math.rotationFromNormalForwardAndTranslation(self.findNormal(castle.position), castle.forward, .{ .y = castle.dimensions.y/2 });
        
        const castleCoord: rl.Vector2 = .{.x = position.x, .y = position.z};
        castle.chunkId = self.renderer.getIdFromCoord(castleCoord) catch 0; // Link rendering to first chunk for compatibility with out-of-map spawning

        self.entities[self.entitycount] = .{.castle = castle}; // Store pointer to entity in list
        self.entitycount += 1; // Increase total entities
    }

    pub fn moveSelection(self: *EntityManager, target: rl.Vector3, owner: MN.Player) void {
        const i_owner:usize = @intFromEnum(owner);

        var i:usize = 0;
        while(i<self.entitycount):(i+=1){
            if (!self.playerSelect[i_owner][i]) continue; // If entity is not selected by player skip command

            const ent = self.entities[i];
            switch (ent) 
            {
                .castle => | castleEntity | 
                {
                    castleEntity.moveTo(target);
                },
                .driver => | driverEntity | 
                {
                    std.debug.print("Missing handling of driver in moveTo: {}\n", .{driverEntity.position});
                }
            }
        }
        // self.deselectAll(owner);

    }

    pub fn draw(self: *EntityManager) void {
        
        var i:usize = 0;
        while (i < self.entitycount):(i+=1){
            const ent: entityPtr = self.entities[i]; // Store entity

            switch (ent){ // Unpack entityPtr type
                .castle => | castleEntity | {
                    if (!castleEntity.idle){
                        castleEntity.model.transform = math.rotationFromNormalForwardAndTranslation(self.findNormal(castleEntity.position), castleEntity.forward, .{ .y = castleEntity.dimensions.y/2 });
                    }
                    if (self.renderer._VisibleInd[castleEntity.chunkId]){
                        castleEntity.draw();
                    }
                    }, 
                .driver => | driverEntity | driverEntity.draw(),
            }
        }
    }


    pub fn selectWithRay(self: *EntityManager, ray: rl.Ray, owner: MN.Player) c_int {
        // Returns number of entities selected/hit by passed ray. Sets entity field .selected to true 
        
        const chunkBoxes = self.renderer.map.boundingBoxes;
        const chunkVisible = self.renderer.getVisible();
        
        var i:usize = 0;
        while (i < chunkBoxes.len):(i+=1){
            if (chunkVisible[i]){
                const collision = rl.GetRayCollisionBox(ray, chunkBoxes[i]);
                if (collision.hit){
                    break;
                }
            }
        }

        var j:usize = 0;
        while (j<self.entitycount):(j+=1){
            const ent = self.entities[j];
            switch (ent) {
                .castle => | castleEntity | {
                    if (castleEntity.chunkId == i) { // If entity is on appropriate chunk
                        const collision = rl.GetRayCollisionMesh(ray, castleEntity.getBoundingMesh(), castleEntity.getTransform()); // Check if it got hit
                        if (collision.hit){
                            return self.selectEntity(j, castleEntity.owner, owner, true);
                        }
                    }
                },
                .driver => | driverEntity | {
                    std.debug.print("Missing handling of driver selection on click: {}\n", .{driverEntity.position});
                }
                
            }
        }
        
        return 0;
    }

    pub fn selectWithin(self: *EntityManager, rec: rl.Rectangle, owner: MN.Player) !c_int {
        // Unoptimized selector: Checks all visible entities
        if (self.entitycount == 0){ // If there are no entities
            return 0; // skip function
        }
        
        const i_owner = @intFromEnum(owner);
        var entitytScreenPos = rl.Vector2{};

        var selectionCount: c_int = 0; // Number of selected entities
        
        var unselectionCount: usize = 0; // Number of entities which were already selected
        var unselectedEnts = try self.allocator.alloc(usize, self.entitycount); // Pointers to all entities within rectangle which have already been selected 
        defer self.allocator.free(unselectedEnts);
        
        
        var i:usize = 0;
        while (i < self.entitycount):(i+=1){
            const ent = self.entities[i];
            switch (ent) 
            {
                .castle => | castleEntity | 
                {
                    entitytScreenPos = rl.GetWorldToScreen(castleEntity.position, self.renderer.camera.*);
                    if (math.withinRect(entitytScreenPos, rec)){ // If entity is within selection
                        if (castleEntity.owner == owner){
                            if (self.playerSelect[i_owner][i]) { // If selected
                                unselectedEnts[unselectionCount] = i;
                                unselectionCount += 1;
                            } else {
                                selectionCount += 1;
                                self.playerSelect[i_owner][i] = true;
                            }
                        }
                    }
                },
                .driver => | driverEntity |
                {
                    std.debug.print("Missing handling of driver selection with rect: {}\n", .{driverEntity.position});
                }
            }
        }

        if (selectionCount == 0) { // If no entities could be selected
            i = 0;
            while(i < unselectionCount):(i+=1){
                self.playerSelect[i_owner][unselectedEnts[i]] = false; // Deselect all within range
            }
            
            return - @as(c_int, @intCast(unselectionCount));
        } else {
            return selectionCount;
        }
    }

    pub fn deselectAll(self: *EntityManager, owner: MN.Player) void {
        const i_owner = @intFromEnum(owner);
        
        var i: usize = 0;
        while (i<self.playerSelect[i_owner].len):(i+=1){
            self.playerSelect[i_owner][i] = false;
        }
    }

    fn selectEntity(self: *EntityManager, entityId: usize, entityOwner: MN.Player, owner: MN.Player, deselect: bool) c_int {
        // Return number of entities selected (negative for deselect)

        const i_owner: usize = @intFromEnum(owner);

        if (entityOwner == owner){ // If unit is owned by player
            if (!self.playerSelect[i_owner][entityId]){ // If not selected
                self.playerSelect[i_owner][entityId] = true; // set object as selected
                return 1;
            } else if (deselect) {
                self.playerSelect[i_owner][entityId] = false; // deselect
                return -1;
            } else { // If already selected and may not be deselected
                return 0;
            }
        }else{
            return 0;
        }


    }

    pub fn findNormal(self: EntityManager, Coord: rl.Vector3) rl.Vector3 {
        // Coord: position on the map where a ray is cast below. Use 0.01 offset in y direction to avoid clipping 
        const ray = rl.Ray{.position = .{.x = Coord.x, .y = Coord.y + 0.01, .z = Coord.z}, .direction = rl.Vector3{.x=0, .y = -1, .z = 0}};
        const mapCoord: rl.Vector2 = .{.x = Coord.x, .y = Coord.z};
        const chunkId: usize = self.renderer.getIdFromCoord(mapCoord) // Try to find id of chunk
            catch |err| {  // If this could not be done (OutOfBounds most likely)
                std.debug.print("Normal could not be found: {}\n", .{err});
                return rl.Vector3{.y = 1}; // Return 0,1,0 vector
            };

        const collision = rl.GetRayCollisionMesh(ray, self.renderer.map.meshes[chunkId], self.renderer.map.transforms[chunkId]);
        return collision.normal;
    }

    pub fn findHeight(self: EntityManager, Coord: rl.Vector3) f32 {
        // Coord: position on the map where a ray is cast below. Use 0.01 offset in y direction to avoid clipping 
        const ray = rl.Ray{.position = .{.x = Coord.x, .y = Coord.y + 10, .z = Coord.z}, .direction = rl.Vector3{.x=0, .y = -1, .z = 0}};
        const mapCoord: rl.Vector2 = .{.x = Coord.x, .y = Coord.z};
        const chunkId: usize = self.renderer.getIdFromCoord(mapCoord) // Try to find id of chunk
            catch |err| {  // If this could not be done (OutOfBounds most likely)
                std.debug.print("Height could not be found: {}\n", .{err});
                return 10.0; // Return 0,1,0 vector
            };

        const collision = rl.GetRayCollisionMesh(ray, self.renderer.map.meshes[chunkId], self.renderer.map.transforms[chunkId]);
        return collision.point.y;
    }

    fn initPlayerSelect (self: *EntityManager, allocator: Allocator, players: usize) !void {
        self.playerSelect = try allocator.alloc([self.entities.len]bool, players); // Allocate memory depending on amount of players
        for (0..players) | i | {
            self.playerSelect[i] = [_]bool{false} ** self.entities.len; // Set default value to false
        }
    }

};


// while (i<self.entitycount):(i+=1){
//     const ent: entityPtr = self.entities[i];
    
//     switch (ent) 
//     {
//         .castle => | castleEntity | 
//         {

//         },
//         .driver => | driverEntity |
//         {
//             std.debug.print("Missing handling of driver in +++++: {}\n", .{driverEntity.position});

//         }
//     }
// }