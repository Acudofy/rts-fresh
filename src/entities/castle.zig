// castle.zig
const std = @import("std");
const rl = @cImport(@cInclude("raylib.h"));

const MN = @import("../globals.zig");
const math = @import("../math.zig");

const EntityManager = @import("entityManager.zig").EntityManager;

pub const Castle = struct {
    id: usize,
    owner: MN.Player,
    model: rl.Model,
    boundingBox: rl.BoundingBox,
    forward: rl.Vector3 = .{.x = 1.0, .y = 0.0, .z = 0.0},
    position: rl.Vector3,
    dimensions: rl.Vector3 = .{.x = 1.5, .y = 1.5, .z = 1.5},
    speed: f32, // m/s
    rotSpeed: f32, // rad/s
    color: rl.Color,
    proximity_threshold: f32,

    manager: *EntityManager,

    idle: bool,
    _target: rl.Vector3 = undefined, // MoveTo position
    chunkId: usize = undefined, // Stores id of chunk the castle is located on
    selected: bool,

    pub fn init(id: usize, location: rl.Vector3, owner: MN.Player, manager: *EntityManager) Castle {
        const meshmodel = rl.GenMeshCube(1.5, 1.5, 1.5);
        var model = rl.LoadModelFromMesh(meshmodel);
        
        const image = rl.LoadImage(MN.MapTextureLoc);
        const texture = rl.LoadTextureFromImage(image);
        rl.UnloadImage(image);
        rl.SetMaterialTexture(&model.materials[0], rl.MATERIAL_MAP_DIFFUSE, texture);
        
        return Castle{
            .id = id, // Always the same as the entity index in entityManager
            .owner = owner,
            .model = model,
            .boundingBox = rl.GetModelBoundingBox(model),
            .position = rl.Vector3{.x = location.x, .y = location.y + 0.75, .z = location.z},
            .speed = 12.0,
            .rotSpeed = std.math.pi,
            .color = rl.ColorFromNormalized(.{ .x = 1, .y = 1, .z = 1, .w = 1 }),
            .proximity_threshold = 3.0,
            .selected = false,
            .idle = true,

            .manager = manager
        };
    }

    pub fn deinit(self: *Castle) void {
        rl.UnloadModel(self.model);
    }

    pub fn moveTo(self: *Castle, target: rl.Vector3) void {
        self.idle = false;
        self._target = target; // Remove y component
    }

    pub fn update(self: *Castle, deltaTime: f32) void {
        if (self.idle) return; // If idle -> Don't move

        var target_vector:rl.Vector3 = math.vector3Subtract(self._target, self.position); // vector which points from self to target position
        
        if (math.vector3Magnitude(target_vector) < MN.PATHING_DEADZONE){
            self.idle = true;
            return;
        }
        std.debug.print("2BTraveled: {}\n", .{@round(math.vector3Magnitude(target_vector))});

        target_vector = math.vector3Normalize(target_vector);

        const rot_dir: f32 = std.math.sign((math.vector3CrossProduct(target_vector, self.forward)).y); // positive = anti-clockwise

        const rot_ang = rot_dir*self.rotSpeed*deltaTime;

        // const past_forward = self.forward;

        self.forward = math.rotateVecAroundY(self.forward, rot_ang);
        // std.debug.print("delta forward: {}\n", .{math.vector3Subtract(self.forward, past_forward)});
        
        const new_Pos = math.vector3Add(self.position, math.vector3Scale(self.forward, deltaTime*self.speed));
        self.position = .{.x = new_Pos.x, .y = self.manager.findHeight(new_Pos), .z = new_Pos.z};
    }

    pub fn setSelected(self: *Castle, value: bool) void {
        self.selected = value;
    }

    pub fn printId(self: Castle) void {
        std.debug.print("castle ID: {} \n", .{self.id});
    }

    pub fn isSelected(self: Castle) bool {
        return self.selected;
    }

    pub fn draw(self: Castle) void {
        rl.DrawModel(self.model, self.position, 1, self.color);
        // const drawColor = if (self.selected) rl.YELLOW else self.color; // Highlight selected castle
        // rl.DrawCube(self.position, self.dimensions.x, self.dimensions.y, self.dimensions.z, drawColor);
    }

    pub fn getPosition(self: Castle) rl.Vector3 {
        return self.position;
    }

    pub fn getProximityThreshold(self: Castle) f32 {
        return self.proximity_threshold;
    }

    pub fn getDimensions(self: Castle) rl.Vector3 {
        return self.dimensions;
    }
    
    pub fn getBoundingBox(self: Castle) rl.BoundingBox {
        return self.boundingBox;
    }

    pub fn getTransform(self: Castle) rl.Matrix {
        return math.matrixAddTranslate(self.model.transform, self.position);
    }

    pub fn getBoundingMesh(self: Castle) rl.Mesh {
        return self.model.meshes[0];
    }

};
