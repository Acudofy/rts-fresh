const std = @import("std");
const rl = @cImport(@cInclude("raylib.h"));

const math = @import("../math.zig");
const util = @import("../utility.zig");

pub const Map = struct {    
    meshes: []rl.Mesh,
    textures: []rl.Texture2D,
    models: []rl.Model,
    positions: []rl.Vector3,
    transforms: []rl.Matrix,
    boundingBoxes: []rl.BoundingBox,
    
    chunks_x: usize,
    chunks_y: usize,
    chunk_width: f32,
    chunk_height: f32,

    allocator: std.mem.Allocator,

    pub fn init( allocator: std.mem.Allocator, height: f32, width: f32, length: f32, height_map_location: []const u8, chunks_x: usize, chunks_y: usize ) !Map {

        const total_chunks = chunks_x * chunks_y;

        const chunkHeight: f32 = height/@as(f32, @floatFromInt(chunks_y));
        const chunkWidth: f32  = width/@as(f32, @floatFromInt(chunks_x));
        
        // const meshes = try allocator.alloc(rl.Mesh, total_chunks);
        const textures = try allocator.alloc(rl.Texture2D, total_chunks);
        const models = try allocator.alloc(rl.Model, total_chunks);
        const positions = try allocator.alloc(rl.Vector3, total_chunks);
        const transforms = try allocator.alloc(rl.Matrix, total_chunks);
        const boundingBoxes = try allocator.alloc(rl.BoundingBox, total_chunks);

        try positionGen(positions, width, height, chunks_x, chunks_y);
        const meshes = try meshGen(allocator, height, width, length, height_map_location, chunks_x, chunks_y);
        util.moveChunks(meshes, positions);
        uploadChunks(meshes);
        try textureGen(textures, height_map_location, chunks_x, chunks_y);
        try modelGen(models, meshes, textures);
        try transformGen(transforms, positions);
        try boundingBoxGen(boundingBoxes, models, positions); // <- Updated this line

        return Map{
            .meshes = meshes,
            .textures = textures,
            .models = models,
            .positions = positions,
            .transforms = transforms,
            .boundingBoxes = boundingBoxes,
            .allocator = allocator,
            .chunks_x = chunks_x,
            .chunks_y = chunks_y,
            .chunk_width = chunkWidth,
            .chunk_height = chunkHeight,
        };
    }

    pub fn deinit(self: *const Map) void {
        // First unload textures
        for (self.textures) |texture| {
            rl.UnloadTexture(texture);
        }
        
        // Then unload models (this will also unload the meshes)
        for (self.meshes) | mesh| {
            util.freeMesh(self.allocator, mesh);
        }
        
        // Free the arrays
        self.allocator.free(self.meshes);
        self.allocator.free(self.textures);
        self.allocator.free(self.models);
        self.allocator.free(self.positions);
        self.allocator.free(self.transforms);
        self.allocator.free(self.boundingBoxes);
    }
};

fn uploadChunks(meshes: []rl.Mesh) void {
    var i:usize = 0;
    while(i<meshes.len):(i+=1){
        rl.UploadMesh(&meshes[i], false);
    }
}

fn textureGen( textures: []rl.Texture2D, height_map_location: []const u8, chunks_x: usize, chunks_y: usize ) !void {
    const HM = rl.LoadImage(height_map_location.ptr);
    defer rl.UnloadImage(HM);

    const chunk_width = @divFloor(HM.width + @as(c_int, @intCast(chunks_x)) - 1, @as(c_int, @intCast(chunks_x)));
    const chunk_height = @divFloor(HM.height + @as(c_int, @intCast(chunks_y)) - 1, @as(c_int, @intCast(chunks_y)));

    for (0..chunks_y) |y| {
        for (0..chunks_x) |x| {
            const i = y * chunks_x + x;
            
            const chunk_start_x = @as(c_int, @intCast(x)) * chunk_width;
            const chunk_start_y = @as(c_int, @intCast(y)) * chunk_height;

            const chunk_width_actual = @min(chunk_width, HM.width - chunk_start_x);
            const chunk_height_actual = @min(chunk_height, HM.height - chunk_start_y);

            const chunk_mask = rl.Rectangle{
                .x = @floatFromInt(chunk_start_x),
                .y = @floatFromInt(chunk_start_y),
                .width = @floatFromInt(chunk_width_actual),
                .height = @floatFromInt(chunk_height_actual),
            };

            const chunk_image = rl.ImageFromImage(HM, chunk_mask);
            textures[i] = rl.LoadTextureFromImage(chunk_image);
            rl.UnloadImage(chunk_image);
        }
    }
}

fn modelGen( models: []rl.Model, meshes: []rl.Mesh, textures: []rl.Texture2D ) !void {
    for (meshes, 0..) |mesh, i| {
        models[i] = rl.LoadModelFromMesh(mesh);
        rl.SetMaterialTexture(&models[i].materials[0], rl.MATERIAL_MAP_DIFFUSE, textures[i]);
    }
}

fn positionGen( positions: []rl.Vector3, width: f32, height: f32, chunks_x: usize, chunks_y: usize ) !void {
    const chunck_width = width / @as(f32, @floatFromInt(chunks_x));
    const chunck_height = height / @as(f32, @floatFromInt(chunks_y));
    std.debug.print("chunck_width: {}\nchunck_height: {}\n", .{chunck_width, chunck_height});

    for (0..chunks_y) |y| {
        for (0..chunks_x) |x| {
            const i = y * chunks_x + x;
            positions[i] = rl.Vector3{
                .x = @as(f32, @floatFromInt(x)) * chunck_width,
                .y = 0.0,
                .z = @as(f32, @floatFromInt(y)) * chunck_height,
            };
            std.debug.print("position {}: ({}, 0, {})", .{i, positions[i].x, positions[i].z});
        }
    }
}

fn transformGen(transforms: []rl.Matrix, positions: []rl.Vector3) !void {
    for (positions, 0..) | pos, i | {
        transforms[i] = math.translateMatrix(pos);
    }
}

fn boundingBoxGen(boundingBoxes: []rl.BoundingBox, models: []rl.Model, positions: []rl.Vector3) !void {
    for (models, positions, 0..) |model, position, i| {

        // Get local space bounding box
        var local_bbox = rl.GetModelBoundingBox(model);
        
        // Transform to world space by offsetting min and max points
        local_bbox.min.x += position.x;
        local_bbox.min.y += position.y;
        local_bbox.min.z += position.z;
        
        local_bbox.max.x += position.x;
        local_bbox.max.y += position.y;
        local_bbox.max.z += position.z;
        
        boundingBoxes[i] = local_bbox;
    }
}

fn meshGen( allocator: std.mem.Allocator, height: f32, width: f32, length: f32, height_map_location: []const u8, chunks_x: usize, chunks_y: usize ) ![]rl.Mesh {
    const HM = rl.LoadImage(height_map_location.ptr);
    defer rl.UnloadImage(HM);

    const mesh = rl.GenMeshHeightmap(HM, rl.Vector3{.x = width, .y = length, .z = height});

    const indicedMesh = try util.addMeshIndicesHashed(allocator, mesh);

    // const meshes = try allocator.alloc(rl.Mesh, chunks_x*chunks_y);
    return try util.chunkMesh(allocator, indicedMesh, chunks_x, chunks_y);

}