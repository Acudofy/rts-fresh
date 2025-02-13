const std = @import("std");
const rl = @cImport(@cInclude("raylib.h"));

const math = @import("../math.zig");
const MN = @import("../globals.zig");

const Allocator:type = std.mem.Allocator;

// const Meshes: type = union(enum) {mesh: rl.Mesh, phMesh: PlaceHolderMesh};

const MapError = error{
        NoFacesInMesh,
        InvalidDimensions,
        TooManyVertices,
        Unexpected,
    };

pub const ModelMap = struct {    
    meshes: []rl.Mesh,
    textures: rl.Texture2D,
    models: []rl.Model,
    modelSwitch: bool = false,
    // models: []rl.Model,
    // positions: []rl.Vector3,
    // transforms: []rl.Matrix,
    boundingBoxes: []rl.BoundingBox,
    
    chunks_x: usize,
    chunks_y: usize,
    // chunk_width: f32,
    // chunk_height: f32,

    allocator: Allocator,

    pub fn init(allocator: Allocator, XChunks: usize, ZChunks: usize, textureLoc: []const u8, MapWidht: f32, MapHeight: f32, MapYHeight:f32, ObjLocation: []const u8) !ModelMap {        
        // Scale mesh of object to desired dimensions. The same scaling to the X axis (MapWidth) will be applied to MapHeight or MaoYHeight if they are provided as 0-values

        const texture = textureFromImage(textureLoc);
        
        var originalMesh = try genMesh(allocator, ObjLocation);
        std.debug.print("Mesh has been generated\n", .{});
        const meshes = try genChunks(allocator, originalMesh, XChunks, ZChunks, MapWidht, MapHeight, MapYHeight);
        originalMesh.deinit();

        var models = try allocator.alloc(rl.Model, meshes.len);
        var BB = try allocator.alloc(rl.BoundingBox, meshes.len);

        var i:usize = 0;
        while (i<meshes.len):(i+=1) {
            models[i] = rl.LoadModelFromMesh(meshes[i]);
            models[i].materials[0].maps[rl.MATERIAL_MAP_DIFFUSE].texture = texture;
            BB[i] = rl.GetMeshBoundingBox(meshes[i]);
        }

        return ModelMap{
            .chunks_x = XChunks, 
            .chunks_y = ZChunks, 
            .meshes = meshes,
            .textures = texture,
            .models = models,
            .boundingBoxes = BB,

            .allocator = allocator,
        };
    }

    pub fn drawMesh(self: ModelMap) void {
        for (self.models, self.boundingBoxes) | model, BB| {
            // if (i==37) continue;
            rl.DrawModel(model, rl.Vector3{.y = -0.5}, 1, rl.WHITE);
            rl.DrawBoundingBox(BB, rl.RED);
            // rl.DrawModel(self.models[1], rl.Vector3{.y = 1.0}, 1, rl.WHITE);
        }
    }

    pub fn deinit(self: *ModelMap) void {
        
        // Free individual components
        freeMeshes(self.allocator, self.meshes);        
        rl.UnloadTexture(self.textures);

        // Free container memory
        self.allocator.free(self.meshes);
        self.allocator.free(self.models);
        self.allocator.free(self.boundingBoxes);
    }
};

fn genMesh(allocator: Allocator, ObjLocation: []const u8) !PlaceHolderMesh {
    // Create mesh from heightMap
    std.debug.print("Trying to generate mesh...\n", .{});
    const image = rl.LoadImage(ObjLocation.ptr);
    const mesh = rl.GenMeshHeightmap(image, rl.Vector3{.x = 10,.y = 2,.z = 10});
    // printMeshInfo(mesh);
    std.debug.print("Mesh generated from HeightMap...\n", .{});

    // Add indices to mesh
    const indicedMesh = try addMeshIndicesHashed(allocator, mesh);
    // printPHMeshInfo(indicedMesh);
    std.debug.print("Created indiced mesh...\n", .{});
    rl.UnloadMesh(mesh);


    return indicedMesh;
}

fn freeMeshes(allocator: Allocator, meshes: []rl.Mesh) void {
    // Used to manually free memory of split Meshes -> Leaves pointer to meshes complete
    var i:usize = 0;
    while(i<meshes.len):(i+=1){
        const indices: []c_ushort = meshes[i].indices[0..@as(usize, @intCast(meshes[i].triangleCount))*3];
        const vertices: []f32 = meshes[i].vertices[0..@as(usize, @intCast(meshes[i].vertexCount))*3];
        const normals: []f32 = meshes[i].normals[0..@as(usize, @intCast(meshes[i].vertexCount))*3];
        const UVs: []f32 = meshes[i].texcoords[0..@as(usize, @intCast(meshes[i].vertexCount))*2];

        allocator.free(indices);
        allocator.free(vertices);
        allocator.free(normals);
        allocator.free(UVs);
    }
}

fn freePHMeshes(meshes: []PlaceHolderMesh) void {
    // Used to manually free memory of split Meshes -> Leaves pointer to meshes complete
    var i:usize = 0;
    while(i<meshes.len):(i+=1){
        meshes[i].deinit();
    }
}

fn freeMesh(allocator: Allocator, mesh: anytype) void {
    // Used to manually free memory of split or scaled Mesh -> Be sure to pass pointer to mesh *Mesh or *const Mesh

    const indices: []c_ushort = mesh.indices[0..@as(usize, @intCast(mesh.triangleCount))*3];
    const vertices: []f32 = mesh.vertices[0..@as(usize, @intCast(mesh.vertexCount))*3];
    const normals: []f32 = mesh.normals[0..@as(usize, @intCast(mesh.vertexCount))*3];
    const UVs: []f32 = mesh.texcoords[0..@as(usize, @intCast(mesh.vertexCount))*2];

    allocator.free(indices);
    allocator.free(vertices);
    allocator.free(normals);
    allocator.free(UVs);
}

fn genChunks(allocator: Allocator, mesh: PlaceHolderMesh, XChunks: usize, ZChunks: usize, MapWidht: f32, MapHeight: f32, MapYHeight: f32) ![]rl.Mesh {
    // Modifies mesh to new scale, The same scaling to the X axis (MapWidth) will be applied to MapHeight or MaoYHeight if they are provided as 0-values

    if (@divFloor(mesh.vertexCount, @as(c_int, @intCast(XChunks*ZChunks))) > std.math.maxInt(c_ushort)) {
        std.debug.print("Vertices expected to be in each chunk out of maximum: {}/{}\n ", .{@divFloor(mesh.vertexCount, @as(c_int, @intCast(XChunks*ZChunks))), std.math.maxInt(c_ushort)});
        return MapError.TooManyVertices;
    }

    // Find Current mesh size
    const BBMesh = mesh.GetPHMeshBoundingBox(); // Get original map size and scale vectors to reach desired dimensions
    const BBMesh_size = math.vector3Subtract(BBMesh.max, BBMesh.min); // Assume min is all smaller dimensions
    // std.debug.print("BBMesh_size: ({}, {}, {})\n", .{BBMesh_size.x, BBMesh_size.y, BBMesh_size.z});

    // Determine scaling of mesh
    if (MapWidht<=0) return MapError.InvalidDimensions; // MapWidth must always be set
    const Width_Map = MapWidht;
    const XScale = Width_Map/BBMesh_size.x;
    const Height_Map = if (MapHeight<=0) XScale*BBMesh_size.z else MapHeight; // If MapHeight == 0 -> set to natural width depending on MapWidth
    // std.debug.print("Height_Map: {}\nBBMesh_size.z: {}\n", .{Height_Map, BBMesh_size.z});
    const ZScale = Height_Map/BBMesh_size.z;
    const HeightY_Map = if (MapYHeight<=0) XScale*BBMesh_size.y else MapYHeight;
    const YScale = (if (!(HeightY_Map == 0)) HeightY_Map else 1.0)/(if (!(BBMesh_size.y == 0)) BBMesh_size.y else 1.0); // Prevent 0 values for flat maps

    // Determine Chunk sizes
    const ChunkXSize: f32 = Width_Map/@as(f32, @floatFromInt(XChunks));
    const ChunkZSize: f32 = Height_Map/@as(f32, @floatFromInt(ZChunks));
    const totChunks: usize = XChunks*ZChunks;

    // Create scaled mesh and self.meshes slice
    const scaledMesh = try scaleMesh(allocator, mesh, XScale, YScale, ZScale);
    var meshes = try allocator.alloc(PlaceHolderMesh, totChunks);
    meshes[0] = scaledMesh; // Store value inside array
    
    // Chop mesh into strips allong x direction and spread them out inside meshes[] -> +1 in index should be along X axis
    var z:usize = 0;
    while (z<ZChunks-1):(z+=1){
        // std.debug.print("z: {}\nChunkZSize: {}\nBBMesh.min.z: {}\nZScale: {}\n", .{z, ChunkZSize, BBMesh.min.z, ZScale});
        std.debug.print("Coordinate: (0, 0, {})\n", .{@as(f32, @floatFromInt(z+1))*ChunkZSize + BBMesh.min.z*ZScale});
        const splitmeshes = splitMesh(allocator, meshes[z*XChunks], rl.Vector3{.z = @as(f32, @floatFromInt(z+1))*ChunkZSize + BBMesh.min.z*ZScale}, rl.Vector3{.x = 1}, 0) 
        catch | err | {
                std.debug.print("splitMesh returned error: {} on cut {}/{}\n freeing all previous meshes\n", .{err, z+1, ZChunks});
                                
                var i:usize = 0;
                while (i<z):(i+=1) {
                    std.debug.print("Free chunk: ({}, {}) in ({}, {}) map\n", .{0, i, XChunks, ZChunks});
                    meshes[i*XChunks].deinit();
                }
                allocator.free(meshes);
                
                return err;
            };
        meshes[z*XChunks].deinit(); // Free memory of combined mesh
        meshes[z*XChunks] = splitmeshes[0]; // Store seperated slice in first spot
        meshes[(z+1)*XChunks] = splitmeshes[1]; // Store remaining bulk in next spot
        allocator.free(splitmeshes);
    }

    // Chop strips up in chunks (cut allong z direction)
    z = 0;
    while(z<ZChunks):(z+=1){ // Used to select strip
        var x:usize = 0;
        while(x<XChunks-1):(x+=1){ // Used to place cut (chunks-1)   
            std.debug.print("Coordinate: ({}, 0, 0)\n", .{@as(f32, @floatFromInt(x+1))*ChunkXSize + BBMesh.min.x*XScale}); 
            const splitmeshes = splitMesh(allocator, meshes[z*XChunks + x], rl.Vector3{.x = @as(f32, @floatFromInt(x+1))*ChunkXSize + BBMesh.min.x*XScale}, rl.Vector3{.z = -1}, x)
            catch | err | {         
                std.debug.print("splitMesh returned error: {} on cut {}/{}\n freeing all previous meshes\n", .{err, x+1+z*(XChunks-1), (XChunks-1)*(ZChunks-1)});                       
                var i:usize = 0;
                while (i<=z):(i+=1) { // For all rows
                    var j:usize = 0;
                    while (j<x+1 or (i < z and j<XChunks)):(j+=1){ // Until row with error (current row: i==z) do full rows, in half row do until column of error
                        std.debug.print("Free chunk: ({}, {}) in ({}, {}) map\n", .{j, i, XChunks, ZChunks});
                        meshes[i*XChunks+j].deinit();
                    }
                }
                while(i<ZChunks):(i+=1){ // Do all remaining first chunks of rows
                    std.debug.print("Free chunk: ({}, {}) in ({}, {}) map\n", .{0, i, XChunks, ZChunks});
                    meshes[i*XChunks].deinit();
                }
                allocator.free(meshes);
                
                return err;
            };

            meshes[z*XChunks+x].deinit();
            meshes[z*XChunks+x] = splitmeshes[0]; // Store chunk into first spot
            // rl.UploadMesh(&meshes[z*XChunks+x], false);
            meshes[z*XChunks+x+1] = splitmeshes[1]; // Store remaining slice in next spot
            allocator.free(splitmeshes);
        } // x+=1
        // rl.UploadMesh(&meshes[z*XChunks+x], false);
    }
    const results = try meshFromPlaceHolders(allocator, meshes);
    allocator.free(meshes);
    return results;
}

fn splitMesh(allocator: Allocator, mesh: PlaceHolderMesh, point: rl.Vector3, dir: rl.Vector3, debug:usize) ![]PlaceHolderMesh {
    const TotVertexCount: u32 = @intCast(mesh.vertexCount);
    const TotTriangleCount: u32 = @intCast(mesh.triangleCount);

    const orth_dir = math.vector3CrossProduct(rl.Vector3{.y = 1}, dir);

    const vertice1 = try allocator.alloc(f32, TotVertexCount*3);
    errdefer allocator.free(vertice1);
    var p1:u32 = 0;
    const vertice2 = try allocator.alloc(f32, TotVertexCount*3);
    errdefer allocator.free(vertice2);
    var p2:u32 = 0;

    const UV1 = try allocator.alloc(f32, TotVertexCount*2);
    errdefer allocator.free(UV1);
    const UV2 = try allocator.alloc(f32, TotVertexCount*2);
    errdefer allocator.free(UV2);

    const normal1 = try allocator.alloc(f32, TotVertexCount*3);
    errdefer allocator.free(normal1);
    const normal2 = try allocator.alloc(f32, TotVertexCount*3);
    errdefer allocator.free(normal2);

    const ids1: []u32 = try allocator.alloc(u32, TotVertexCount);
    errdefer allocator.free(ids1);
    const ids2: []u32 = try allocator.alloc(u32, TotVertexCount);
    errdefer allocator.free(ids2);


    // Split mesh in 2
    var i:u32 = 0;
    while(i < TotVertexCount):(i+=1){
        const v_loc = rl.Vector3{
            .x = mesh.vertices[i*3] - point.x,
            .y = mesh.vertices[i*3+1] - point.y,
            .z = mesh.vertices[i*3+2] - point.z
            };
        if (math.vector3DotProduct(v_loc, orth_dir) > 0) { // > 0 = 1 side, <= 0 is other
            vertice1[p1*3] = mesh.vertices[i*3];
            vertice1[p1*3+1] = mesh.vertices[i*3+1];
            vertice1[p1*3+2] = mesh.vertices[i*3+2];
            
            normal1[p1*3] = mesh.normals[i*3];
            normal1[p1*3+1] = mesh.normals[i*3+1];
            normal1[p1*3+2] = mesh.normals[i*3+2];

            UV1[p1*2] = mesh.texcoords[i*2];
            UV1[p1*2+1] = mesh.texcoords[i*2+1];
            
            ids1[i] = p1;

            p1 += 1;
        } else {
            vertice2[p2*3] = mesh.vertices[i*3];
            vertice2[p2*3+1] = mesh.vertices[i*3+1];
            vertice2[p2*3+2] = mesh.vertices[i*3+2];

            normal2[p2*3] = mesh.normals[i*3];
            normal2[p2*3+1] = mesh.normals[i*3+1];
            normal2[p2*3+2] = mesh.normals[i*3+2];

            UV2[p2*2] = mesh.texcoords[i*2];
            UV2[p2*2+1] = mesh.texcoords[i*2+1];

            ids2[i] = p2;
            ids1[i] = TotVertexCount;

            p2 += 1;
        }
    }
    const chunk1Vertices = p1;
    const chunk2Vertices = p2;

    // Refactor indices such that all vertices with an index below n belong to chunk 1 and all vertices above n fall within chunk 2 
    const connection_mask1: []bool = try allocator.alloc(bool, TotTriangleCount); // Used to keep track of which faces belong to chunk 1
    errdefer allocator.free(connection_mask1);
    const connection_mask2: []bool = try allocator.alloc(bool, TotTriangleCount); // Used to keep track of which faces belong to chunk 2
    errdefer allocator.free(connection_mask2);
    const other_vertex_offset: []u2 = try allocator.alloc(u2, TotTriangleCount); // Used to keep track which singular vertice falls in the other chunk | vertex 0 -> vertex 1 and 2 fall inside other chunk etc.
    errdefer allocator.free(other_vertex_offset);

    const editable_indices = try allocator.alloc(u32, TotTriangleCount*3);
    errdefer allocator.free(editable_indices);

    std.mem.copyForwards(u32, editable_indices, mesh.indices[0..TotTriangleCount*3]);
    
    i = 0;
    while (i<ids1.len):(i+=1){if (ids1[i] == TotVertexCount) ids1[i] = ids2[i] + chunk1Vertices;} // Merge the 2 id lists, offsetting the ids in chunk 2 with the last id in id1

    i = 0; // replace indices to seperate chunk 1 & 2
    while (i<editable_indices.len):(i+=1) {
        editable_indices[i] = ids1[editable_indices[i]];
    }
    // while (i<chunk1Vertices):(i+=1) {
    //     replace(editable_indices, mesh.indices, ids1[i], i); // ids in chunk 1 are running 1..p1 TODO: SPEED UP THIS ROUTINE USING HASHMAPS?
    // }

    // i = 0;
    // while (i<chunk2Vertices):(i+=1) {
    //     replace(editable_indices, mesh.indices, ids2[i], chunk1Vertices+i); // ids in chunk 2 are running p1..end
    // }

    // Seperate connections (indices) into chunk 1, 2, or neither
    i = 0;
    p1 = 0; // Now storing number of faces in chunk 1
    p2 = 0;
    while (i<TotTriangleCount):(i+=1){
        const b1 = editable_indices[i*3] < chunk1Vertices;
        const b2 = editable_indices[i*3+1] < chunk1Vertices;
        const b3 = editable_indices[i*3+2] < chunk1Vertices;
        
        
        if (b1 and b2 and b3) { // If all vertices of triangle fall within chunk 1
            connection_mask1[i] = true;
            p1+=1;
        } else if (!b1 and !b2 and !b3) { // If it all falls within chunk 2
            connection_mask2[i] = true;
            p2 +=1;
        } else {
            // std.debug.print("b1: {}\nb2: {}\nb3: {}\nchunk1Vertices: {}\n", .{b1, b2, b3, chunk1Vertices});
            other_vertex_offset[i] = find3bool([_]bool{b1, b2, b3}, !((b1 and b2) or (b1 and b3) or (b2 and b3))); // Search for bool index in minority state -> if any (bx and bx) -> 2 vertices in chunk 1 -> look for vertice in chunk 2 (false) 
            // std.debug.print("Other vertex offset: {}\n", .{other_vertex_offset[i]});
        }
    }

    // store faces into respective indices and divide up ambiguous faces between the 2 chunks
    const indice1 = try allocator.alloc(u32, (TotTriangleCount-p2)*3); // p1 = amount of faces in chunk 1 -> total-p2 = amount of possible faces in chunk 1 (including edge-faces)
    errdefer allocator.free(indice1);
    // std.debug.print("TotTriangleCount - p1 = {} - {} = {}\n", .{TotTriangleCount, p1, TotTriangleCount - p1});
    const indice2 = try allocator.alloc(u32, (TotTriangleCount - p1)*3); // Same for p2 and chunk 2
    errdefer allocator.free(indice2);
    
    var added_vertices1:u32 = 0; // Keep track of added vertices
    var added_vertices2:u32 = 0;

    i = 0;
    p1 = 0; 
    p2 = 0;
    while (i<TotTriangleCount):(i+=1) {
        if(connection_mask1[i]) {
            indice1[p1*3] = editable_indices[i*3];
            indice1[p1*3+1] = editable_indices[i*3+1];
            indice1[p1*3+2] = editable_indices[i*3+2];
            p1+=1;
        } else if (connection_mask2[i]){
            indice2[p2*3] = editable_indices[i*3]-chunk1Vertices; // First index of chunk 2 is p1+1 -> should be changed to 0 
            indice2[p2*3+1] = editable_indices[i*3+1]-chunk1Vertices;
            indice2[p2*3+2] = editable_indices[i*3+2]-chunk1Vertices;
            p2+=1;
        } else {
            const minorityIndiceOffset = other_vertex_offset[i]; // returns indice of vertex within face which is in 'other chunk' (0..3) 
            const OtherVertexInd:u32 = editable_indices[i*3 + @as(u32, @intCast(minorityIndiceOffset))]; // returns index of vertex which is *alone* in 'other' chunk (0..mesh.vertices.len) | Need usize cast to be able to reach desired indice values
            if (OtherVertexInd >= chunk1Vertices) {// minority vertex belongs to chunk 2 -> most vertices fall in chunk 1
                const indexOfOtherInVertex2 = OtherVertexInd - chunk1Vertices; // Correct for offset (n) in total vertex indices (-= n)
                // Create new vertex for face to attach to
                vertice1[(chunk1Vertices + added_vertices1)*3] = vertice2[indexOfOtherInVertex2*3];
                vertice1[(chunk1Vertices + added_vertices1)*3+1] = vertice2[indexOfOtherInVertex2*3+1];
                vertice1[(chunk1Vertices + added_vertices1)*3+2] = vertice2[indexOfOtherInVertex2*3+2];

                // Create new normal for created vertex
                normal1[(chunk1Vertices + added_vertices1)*3] = normal2[indexOfOtherInVertex2*3];
                normal1[(chunk1Vertices + added_vertices1)*3+1] = normal2[indexOfOtherInVertex2*3+1];
                normal1[(chunk1Vertices + added_vertices1)*3+2] = normal2[indexOfOtherInVertex2*3+2];

                // Create new UVs for created vertex
                UV1[(chunk1Vertices + added_vertices1)*2] = UV2[indexOfOtherInVertex2*2];
                UV1[(chunk1Vertices + added_vertices1)*2+1] = UV2[indexOfOtherInVertex2*2+1];

                // Add face to indices
                indice1[p1*3] = if (minorityIndiceOffset != 0) editable_indices[i*3] else chunk1Vertices + added_vertices1; // Use normal index unless it is the index of the newly created vertex
                indice1[p1*3+1] = if (minorityIndiceOffset != 1) editable_indices[i*3+1] else chunk1Vertices + added_vertices1;
                indice1[p1*3+2] = if (minorityIndiceOffset != 2) editable_indices[i*3+2] else chunk1Vertices + added_vertices1;

                added_vertices1 += 1;
                p1+=1;
            } else { // minority vertex belongs in chunk 1 -> most vertices fall in chunk 2
                const indexOfOtherInVertex1 = OtherVertexInd;
                // Create new vertex for face to attach to
                // std.debug.print("indexOfOtherInVertex1: {} \nvertice1.len: {}\n", .{indexOfOtherInVertex1, vertice1.len});
                vertice2[(chunk2Vertices + added_vertices2)*3] = vertice1[indexOfOtherInVertex1*3]; // @as(usize, @intCast(
                vertice2[(chunk2Vertices + added_vertices2)*3+1] = vertice1[indexOfOtherInVertex1*3+1];
                vertice2[(chunk2Vertices + added_vertices2)*3+2] = vertice1[indexOfOtherInVertex1*3+2];

                // Create new normal for created vertex
                normal2[(chunk2Vertices + added_vertices2)*3] = normal1[indexOfOtherInVertex1*3];
                normal2[(chunk2Vertices + added_vertices2)*3+1] = normal1[indexOfOtherInVertex1*3+1];
                normal2[(chunk2Vertices + added_vertices2)*3+2] = normal1[indexOfOtherInVertex1*3+2];

                // Create new UVs for created vertex
                UV2[(chunk2Vertices + added_vertices2)*2] = UV1[indexOfOtherInVertex1*2];
                UV2[(chunk2Vertices + added_vertices2)*2+1] = UV1[indexOfOtherInVertex1*2+1];

                // Add face to indices
                indice2[p2*3] =    if (minorityIndiceOffset != 0)  editable_indices[i*3]-chunk1Vertices   else chunk2Vertices + added_vertices2; // Use normal index unless it is the index of the newly created vertex
                indice2[p2*3+1] =  if (minorityIndiceOffset != 1)  editable_indices[i*3+1]-chunk1Vertices else chunk2Vertices + added_vertices2;
                indice2[p2*3+2] =  if (minorityIndiceOffset != 2)  editable_indices[i*3+2]-chunk1Vertices else chunk2Vertices + added_vertices2;
                
                added_vertices2 += 1;
                p2+=1;
            } 
        }
    }

    const chunk1_Vertices:u32 = chunk1Vertices + added_vertices1;
    const chunk2_Vertices:u32 = chunk2Vertices + added_vertices2;
    
    // Check validity of meshes
    // Return errors if a mesh has 0 faces to render -> will return an error on freeing memory (I think? solved some other errors which might be related so maybe not anymore)
    if (p1 == 0 or p2 == 0) { // Check if meshes will have enough triangles
        return MapError.NoFacesInMesh;
        // IF CUT SHOULD BE WITHIN MESH BOUNDS -> TRY ROTATING CUTTING DIRECTION
    }

    // Trimming memory to correct size
    const vertices1 = try allocator.alloc(f32, chunk1_Vertices*3);
    errdefer allocator.free(vertices1);
    std.mem.copyForwards(f32, vertices1, vertice1[0..chunk1_Vertices*3]);
    const vertices2 = try allocator.alloc(f32, chunk2_Vertices*3);
    errdefer allocator.free(vertices2);
    std.mem.copyForwards(f32, vertices2, vertice2[0..chunk2_Vertices*3]);

    const indices1 = try allocator.alloc(u32, p1*3);
    errdefer allocator.free(indices1);
    std.mem.copyForwards(u32, indices1, indice1[0..p1*3]);
    const indices2 = try allocator.alloc(u32, p2*3);
    errdefer allocator.free(indices2);
    std.mem.copyForwards(u32, indices2, indice2[0..p2*3]);

    const normals1 = try allocator.alloc(f32, chunk1_Vertices*3);
    errdefer allocator.free(normals1);
    std.mem.copyForwards(f32, normals1, normal1[0..chunk1_Vertices*3]);
    const normals2 = try allocator.alloc(f32, chunk2_Vertices*3);
    errdefer allocator.free(normals2);
    std.mem.copyForwards(f32, normals2, normal2[0..chunk2_Vertices*3]);

    const UVs1 = try allocator.alloc(f32, chunk1_Vertices*2);
    errdefer allocator.free(UVs1);
    std.mem.copyForwards(f32, UVs1, UV1[0..chunk1_Vertices*2]);
    const UVs2 = try allocator.alloc(f32, chunk2_Vertices*2);
    errdefer allocator.free(UVs2);
    std.mem.copyForwards(f32, UVs2, UV2[0..chunk2_Vertices*2]);

    // Construct meshes
    var meshes = try allocator.alloc(PlaceHolderMesh, 2);
    errdefer allocator.free(meshes);
    meshes[0] = PlaceHolderMesh{.allocator = allocator};
    meshes[0].triangleCount = @intCast(p1);
    meshes[0].indices = indices1;
    meshes[0].vertexCount = @intCast(chunk1_Vertices);
    meshes[0].vertices = vertices1;
    meshes[0].texcoords = UVs1;
    meshes[0].normals = normals1;

    meshes[1] = PlaceHolderMesh{.allocator = allocator};
    meshes[1].triangleCount = @intCast(p2);
    meshes[1].indices = indices2;
    meshes[1].vertexCount = @intCast(chunk2_Vertices);
    meshes[1].vertices = vertices2;
    meshes[1].texcoords = UVs2;
    meshes[1].normals = normals2;

    if (debug == MN.X_CHUNKS-2) std.debug.print("", .{});
    // Free up memory
    allocator.free(connection_mask1);
    allocator.free(connection_mask2);
    allocator.free(other_vertex_offset);
    allocator.free(editable_indices);
    allocator.free(ids1);
    allocator.free(ids2);

    allocator.free(vertice1);
    allocator.free(vertice2);
    allocator.free(indice1);
    allocator.free(indice2);
    allocator.free(normal1);
    allocator.free(normal2);
    allocator.free(UV1);
    allocator.free(UV2);

    return meshes;
}

fn scaleMesh(allocator: Allocator, mesh: PlaceHolderMesh, XScale:f32, YScale:f32, ZScale:f32) !PlaceHolderMesh {
    // Scales PlaceholderMesh from origin (0,0,0)

    std.debug.print("Scaling: ({}, {}, {})\n", .{XScale, YScale, ZScale});
    
    // Store constants to be used in indicing
    const TriangleCount:usize = @intCast(mesh.triangleCount);
    const VertexCount:usize = @intCast(mesh.vertexCount);

    // var ScMesh = try allocator.alloc(rl.Mesh, 1);
    const indices = try allocator.alloc(u32, TriangleCount*3);
    const vertices = try allocator.alloc(f32, VertexCount*3);
    const normals = try allocator.alloc(f32, VertexCount*3);
    const UVs = try allocator.alloc(f32, VertexCount*2);
    
    var ScMesh = PlaceHolderMesh{.allocator = allocator};
    std.mem.copyForwards(u32, indices, mesh.indices[0..TriangleCount*3]);
    // std.mem.copyForwards(c_ushort, vertices, mesh.vertices);
    std.mem.copyForwards(f32, normals, mesh.normals[0..VertexCount*3]);
    std.mem.copyForwards(f32, UVs, mesh.texcoords[0..VertexCount*2]);
    
    var i:usize = 0;
    while(i<mesh.vertexCount):(i+=1){
        vertices[i*3] =  mesh.vertices[i*3]*XScale;
        vertices[i*3+1] =  mesh.vertices[i*3+1]*YScale;
        vertices[i*3+2] =  mesh.vertices[i*3+2]*ZScale;
    }

    ScMesh.indices = indices;
    ScMesh.vertices = vertices;
    ScMesh.normals = normals;
    ScMesh.texcoords = UVs;
    ScMesh.triangleCount = mesh.triangleCount;
    ScMesh.vertexCount = mesh.vertexCount;

    std.debug.print("Scaled Mesh\n", .{});

    return ScMesh;
    
}

fn textureFromImage(imageLoc: []const u8) rl.Texture {
    const image = rl.LoadImage(imageLoc.ptr);
    const texture = rl.LoadTextureFromImage(image);
    rl.UnloadImage(image);
    return texture;

}

fn replace(list: []u32, reference_list: []u32, value: u32, replacevalue: u32) void {
    var i:u32 = 0;
    while(i<list.len):(i+=1){
        if (reference_list[i] == value) {
            list[i] = replacevalue;
        } 
    }
}

fn printMeshInfo(mesh: rl.Mesh) void {
    const indiced = mesh.indices != null;
    if (indiced) std.debug.print("Mesh is indiced\n", .{}) else std.debug.print("Mesh is non-indiced\n", .{});
    
    std.debug.print("vertexCount: {}\n", .{mesh.vertexCount});
    std.debug.print("triangleCount: {}\n", .{mesh.triangleCount});
    std.debug.print("vaoID: {}\n", .{mesh.vaoId});
    if (mesh.vboId != null) std.debug.print("vboID: {}\n", .{mesh.vboId.*}) else std.debug.print("vboID: NA", .{});

    var i_vertex:usize = 0;
    while(i_vertex < mesh.vertexCount):(i_vertex+=1){
        std.debug.print("===== VERTEX {} =====\n", .{i_vertex});
        std.debug.print("Vertex position: ({d}, {d}, {d})\n", .{mesh.vertices[i_vertex*3], mesh.vertices[i_vertex*3+1], mesh.vertices[i_vertex*3+2]});
        std.debug.print("Vertex UV (Texcoords): ({d}, {d})\n", .{mesh.texcoords[i_vertex*2], mesh.texcoords[i_vertex*2+1]});
        if (indiced and i_vertex < mesh.triangleCount*3) std.debug.print("Indices: {}, {}, {}\n", .{mesh.indices[i_vertex*3], mesh.indices[i_vertex*3+1], mesh.indices[i_vertex*3+2]}); 
    }
}

fn printPHMeshInfo(mesh: PlaceHolderMesh) !void {
    // Assumes mesh is always indiced
    
    std.debug.print("vertexCount: {}\n", .{mesh.vertexCount});
    std.debug.print("triangleCount: {}\n", .{mesh.triangleCount});

    var i_vertex:usize = 0;
    while(i_vertex < mesh.vertexCount):(i_vertex+=1){
        std.debug.print("===== VERTEX {} =====\n", .{i_vertex});
        std.debug.print("Vertex position: ({d}, {d}, {d})\n", .{mesh.vertices[i_vertex*3], mesh.vertices[i_vertex*3+1], mesh.vertices[i_vertex*3+2]});
        std.debug.print("Vertex UV (Texcoords): ({d}, {d})\n", .{mesh.texcoords[i_vertex*2], mesh.texcoords[i_vertex*2+1]});
        std.debug.print("Indices: {}, {}, {}\n", .{mesh.indices[i_vertex*3], mesh.indices[i_vertex*3+1], mesh.indices[i_vertex*3+2]}); 
        if(i_vertex+1 == 628) return MapError.Unexpected;
    }
}

fn find3bool(list: [3]bool, boolean: bool) u2 {
    // Return first indice in which list[i] == boolean
    var i:usize = 0;
    while(i<list.len):(i+=1){
        if (list[i] == boolean) return @intCast(i);
    }
    return @intCast(i); // If nothing can be found return i -> Out of bounds error if used
}

fn meshFromPlaceHolders(allocator: Allocator, PHmeshes: []PlaceHolderMesh) ![]rl.Mesh {
    // Create meshes from values inside 'PHmeshes', deinits PHmeshes & uploads rl.Mesh meshes
    
    const meshes = try allocator.alloc(rl.Mesh, PHmeshes.len);
    errdefer allocator.free(meshes);

    var i:usize = 0;
    while(i<meshes.len):(i+=1){
        const indices = try allocator.alloc(c_ushort, PHmeshes[i].indices.len);
        errdefer allocator.free(indices);
        var j:usize = 0;
        while(j < indices.len):(j+=1) indices[j] = @intCast(PHmeshes[i].indices[j]); // Cast indices back to c_ushort
        allocator.free(PHmeshes[i].indices);
        // Transfer pointers to new mesh struct (same memory being referenced: Do not free)
        meshes[i] = rl.Mesh{};
        meshes[i].indices = indices.ptr;
        meshes[i].vertices = PHmeshes[i].vertices.ptr;
        meshes[i].normals = PHmeshes[i].normals.ptr;
        meshes[i].texcoords = PHmeshes[i].texcoords.ptr;
        meshes[i].triangleCount = PHmeshes[i].triangleCount;
        meshes[i].vertexCount = PHmeshes[i].vertexCount;

        rl.UploadMesh(&meshes[i], false);
    }
    
    return meshes;
}


fn addMeshIndicesHashed(allocator: Allocator, mesh: rl.Mesh) !PlaceHolderMesh{
    // Returns same mesh as PlaceHolderMesh type
    const VertexCount:usize = @intCast(mesh.vertexCount);
    const TriangleCount:usize = @intCast(mesh.triangleCount);
    
    // const f32Precision = MN.f32Precision;
    
    if (mesh.indices != null) { // If mesh already uses indices return same mesh
        const indices: []u32 = try allocator.alloc(u32, TriangleCount);
        errdefer allocator.free(indices);
        
        var i:usize = 0; // Cast c_ushort to u16
        while(i<TriangleCount):(i+=1){
            indices[i] = @intCast(mesh.indices[i]);
        }

        const result = PlaceHolderMesh{
            .allocator = allocator,
            .indices = indices,
            .vertices = mesh.vertices[0..VertexCount*3],
            .normals = mesh.normals[0..VertexCount*3],
            .texcoords = mesh.texcoords[0..VertexCount*2],
            .triangleCount = mesh.triangleCount,
            .vertexCount = mesh.vertexCount,
        };

        return result; 
    }
    // Else continue with creating indiced PlaceHolderMesh from mesh
    
    // Make unique-vertex arrays & add indices
    const vertices = try allocator.alloc(f32, @intCast(VertexCount*3)); // Store trimmed list of vertices
    errdefer allocator.free(vertices);
    const normals = try allocator.alloc(f32, @intCast(VertexCount*3)); // Store trimmed list of normals
    errdefer allocator.free(normals);
    const UVs = try allocator.alloc(f32, @intCast(VertexCount*2)); // Store trimmed list of texCoords
    errdefer allocator.free(UVs);

    const indices = try allocator.alloc(u32, @intCast(TriangleCount*3)); // Stores indices to vertices
    errdefer allocator.free(indices);
    
    // const indiced = try allocator.alloc(bool, @intCast(VertexCount));
    // errdefer allocator.free(indiced);
    // var i:usize = 0;
    // while(i<indiced.len):(i+=1) indiced[i] = false; // Set all values to false by default

    if (VertexCount>std.math.maxInt(u32)) return MapError.TooManyVertices; // Could still be fine since vertexCount will decrease due to operation

    // const values = struct {indice: u32};

    // Create hashmap
    var hashmap = std.hash_map.AutoHashMap([3]u32, u32).init(allocator); // Make hashmap with key 'Vertex' (searched for ([3]f32 cast to [3]u32)) with value of indice of point (meta data)
    try hashmap.ensureTotalCapacity(@intCast(VertexCount));

    var i:u32 = 0; // Stored vertex to be checked
    var p:u32 = 0; // Counts number of unique vertices 
    while(i < VertexCount):(i+=1){
        if (i % 10000000 == 0) std.debug.print("Checked {}/{} vertices\n", .{i, VertexCount});

        
        const vertice:[3]u32 = .{   @bitCast(mesh.vertices[i*3]),
                                    @bitCast(mesh.vertices[i*3+1]),
                                    @bitCast(mesh.vertices[i*3+2])}; // Stores to-be-processed vertice | Cast floats to u32 to hash them normally -> Assumes identical values for same-position vertices: No precision error, No -0.0/+0.0 or NaN shenanigans

        const getOrPutResults = hashmap.getOrPutAssumeCapacity(vertice); // place vertex in hashmap if non-existent
        
        if (!getOrPutResults.found_existing) { // If entry does not exists
            // Store unique vertice, normals, texcoords, and indice
            const v0:f32 = @bitCast(vertice[0]);
            const v1:f32 = @bitCast(vertice[1]);
            const v2:f32 = @bitCast(vertice[2]);
            
            // if (i%10000 == 0){
            //     const ver = .{v0, v1, v2};

            //     if (std.math.isNegativeZero(ver[0]) or std.math.isPositiveZero(ver[0])) std.debug.print("value v0 isZero: {}\n", .{ver[0]});
            //     if (std.math.isNegativeZero(ver[1]) or std.math.isPositiveZero(ver[1])) std.debug.print("value v0 isZero: {}\n", .{ver[1]});
            //     if (std.math.isNegativeZero(ver[2]) or std.math.isPositiveZero(ver[2])) std.debug.print("value v0 isZero: {}\n", .{ver[2]});
            // }

            vertices[p*3] = v0;
            vertices[p*3+1] = v1;
            vertices[p*3+2] = v2;

            normals[p*3] = mesh.normals[i*3];
            normals[p*3+1] = mesh.normals[i*3+1];
            normals[p*3+2] = mesh.normals[i*3+2];

            UVs[p*2] = mesh.texcoords[i*2];
            UVs[p*2+1] = mesh.texcoords[i*2+1];

            indices[i] = p;
            
            // Store meta deta (pointer to unique vertice)
            getOrPutResults.value_ptr.* = p;
            p +=1; // Increase number of unique vertices
        } else { // If vertice already exists
            indices[i] = getOrPutResults.value_ptr.*; // Reference unique vertex
        }
    }

    const vertexCount = p;

    // Indices are found, unique values are storred

    // Free memory
    hashmap.deinit();
    
    // Trim memory
    const vertices_ = try allocator.alloc(f32, vertexCount*3); // (p1 = Number of unique vertices)*3 = xyz
    errdefer allocator.free(vertices_);

    const normals_ = try allocator.alloc(f32, vertexCount*3); // (p1 = Number of unique vertices)*3 = xyz
    errdefer allocator.free(normals_);

    const UVs_ = try allocator.alloc(f32, vertexCount*2); // (p1 = Number of unique vertices)*3 = xyz
    errdefer allocator.free(UVs_);


    std.mem.copyForwards(f32, vertices_, vertices[0..vertexCount*3]);
    std.mem.copyForwards(f32, normals_, normals[0..vertexCount*3]);
    std.mem.copyForwards(f32, UVs_, UVs[0..vertexCount*2]);
    

    allocator.free(vertices);
    allocator.free(normals);
    allocator.free(UVs);

    var result = PlaceHolderMesh{.allocator = allocator};
    result.indices = indices;
    result.vertices = vertices_;
    result.texcoords = UVs_;
    result.normals = normals_;
    result.vertexCount = @intCast(vertexCount);
    result.triangleCount = @intCast(TriangleCount);

    // rl.UploadMesh(result, false);

    return result;
}

// fn addMeshIndices(allocator: Allocator, mesh: rl.Mesh) !PlaceHolderMesh{
//     // Returns same mesh as PlaceHolderMesh type
//     const VertexCount:usize = @intCast(mesh.vertexCount);
//     const TriangleCount:usize = @intCast(mesh.triangleCount);
    
    
//     if (mesh.indices != null) { // If mesh already uses indices return same mesh
//         const indices: []u32 = try allocator.alloc(u32, TriangleCount);
//         errdefer allocator.free(indices);
        
//         var i:usize = 0; // Cast c_ushort to u16
//         while(i<TriangleCount):(i+=1){
//             indices[i] = @intCast(mesh.indices[i]);
//         }

//         const result = PlaceHolderMesh{
//             .allocator = allocator,
//             .indices = indices,
//             .vertices = mesh.vertices[0..VertexCount*3],
//             .normals = mesh.normals[0..VertexCount*3],
//             .texcoords = mesh.texcoords[0..VertexCount*2],
//             .triangleCount = mesh.triangleCount,
//             .vertexCount = mesh.vertexCount,
//         };

//         return result; 
//     }
//     // Else continue with creating indiced PlaceHolderMesh from mesh
    
//     // Make unique-vertex arrays & add indices
//     const vertices = try allocator.alloc(f32, @intCast(VertexCount*3)); // Store trimmed list of vertices
//     errdefer allocator.free(vertices);
//     const normals = try allocator.alloc(f32, @intCast(VertexCount*3)); // Store trimmed list of normals
//     errdefer allocator.free(normals);
//     const UVs = try allocator.alloc(f32, @intCast(VertexCount*2)); // Store trimmed list of texCoords
//     errdefer allocator.free(UVs);

//     const indices = try allocator.alloc(u32, @intCast(TriangleCount*3)); // Stores indices to vertices
//     errdefer allocator.free(indices);
    
//     const indiced = try allocator.alloc(bool, @intCast(VertexCount));
//     errdefer allocator.free(indiced);
//     var i:usize = 0;
//     while(i<indiced.len):(i+=1) indiced[i] = false; // Set all values to false by default

//     if (VertexCount>std.math.maxInt(u32)) return MapError.TooManyVertices; // Could still be fine since vertexCount will decrease due to operation

//     var p1:u32 = 0; // Stores index of last unique vertice
//     i = 0; // Stores index of triangle indices/original mesh vertices
//     while(i<VertexCount):(i+=1) {
//         if (i%10 == 0) std.debug.print("Checked {}/{} vertices...\n", .{i, mesh.vertexCount});
//         if (indiced[i]) continue; // If already indiced->skip
        
//         const point: [3]f32 = .{mesh.vertices[i], mesh.vertices[i+1], mesh.vertices[i+2]};
        
//         // Store unique vertex(values) into 'vertices'
//         vertices[p1*3] = point[0];
//         vertices[p1*3+1] = point[1];
//         vertices[p1*3+2] = point[2];
        
//         normals[p1*3] = mesh.normals[i*3];
//         normals[p1*3+1] = mesh.normals[i*3+1];
//         normals[p1*3+2] = mesh.normals[i*3+2];
        
//         UVs[p1*3] = mesh.texcoords[i*3];
//         UVs[p1*3+1] = mesh.texcoords[i*3+1];

//         // Set indices to current vertex
//         indices[i] = p1;
//         // indices[i*3+1] = p1*3+1;
//         // indices[i*3+2] = p1*3+2;

//         try checkDuplicateVerticesMT(mesh.vertices, indices, point, p1, indiced, mesh.vertexCount);
//         // Check all subsequent points for duplicates
//         // var j:usize = i+1;
//         // while(j<VertexCount):(j+=1){
//         //     if (indiced[j]) continue; // If already indiced->skip

//         //     if (point[0] == mesh.vertices[j*3] and point[1] == mesh.vertices[j*3+1] and point[2] == mesh.vertices[j*3+2]) { // If point is the same
//         //         indiced[j] = true; // Set point as being indiced

//         //         indices[j] = p1; // Set indice to original unique-point
//         //         // indices[j*3+1] = p1*3+1;
//         //         // indices[j*3+2] = p1*3+2;
//         //     } // Else check next point

//         // }
//         p1 +=1; // increase unique vertex index
//     }

//     // Store total unique vertex count
//     const vertexCount = p1-1;

//     // Free memory
//     allocator.free(indiced);
    
//     // Trim memory
//     const vertices_ = try allocator.alloc(f32, vertexCount*3); // (p1 = Number of unique vertices)*3 = xyz
//     errdefer allocator.free(vertices_);

//     const normals_ = try allocator.alloc(f32, vertexCount*3); // (p1 = Number of unique vertices)*3 = xyz
//     errdefer allocator.free(normals_);

//     const UVs_ = try allocator.alloc(f32, vertexCount*3); // (p1 = Number of unique vertices)*3 = xyz
//     errdefer allocator.free(UVs_);


//     std.mem.copyForwards(f32, vertices_, vertices[0..vertexCount*3]);
//     std.mem.copyForwards(f32, normals_, normals[0..vertexCount*3]);
//     std.mem.copyForwards(f32, UVs_, UVs[0..vertexCount*2]);
    

//     allocator.free(vertices);
//     allocator.free(normals);
//     allocator.free(UVs);

//     var result = PlaceHolderMesh{.allocator = allocator};
//     result.indices = indices;
//     result.vertices = vertices_;
//     result.texcoords = UVs_;
//     result.normals = normals_;
//     result.vertexCount = @intCast(vertexCount);
//     result.triangleCount = @intCast(TriangleCount);

//     // rl.UploadMesh(result, false);

//     return result;
// }

pub const PlaceHolderMesh = struct { 
    allocator: Allocator,
    indices: []u32 = undefined,
    vertices: []f32 = undefined,
    normals: []f32 = undefined,
    texcoords: []f32 = undefined,
    triangleCount: c_int = undefined,
    vertexCount: c_int = undefined,

    fn GetPHMeshBoundingBox(self: PlaceHolderMesh) rl.BoundingBox{
        // Get min and max vertex to construct bounds (AABB)
        var minVertex: rl.Vector3 = .{};
        var maxVertex: rl.Vector3 = .{};

        if (self.vertices.len != 0)
        {
            // std.debug.print("Checking BoundingBox...\n", .{});
            
            minVertex = rl.Vector3{ .x = self.vertices[0], .y = self.vertices[1], .z = self.vertices[2] };
            maxVertex = rl.Vector3{ .x = self.vertices[0], .y = self.vertices[1], .z = self.vertices[2] };

            var i:usize = 1;
            while(i<self.vertexCount):(i+=1)
            {
                // std.debug.print("Checked vertex {}: ({}, {}, {})\n", .{i, self.vertices[i*3], self.vertices[i*3+1], self.vertices[i*3+2]});
                minVertex = math.Vector3Min(minVertex, rl.Vector3{ .x = self.vertices[i*3], .y = self.vertices[i*3 + 1], .z = self.vertices[i*3 + 2] });
                maxVertex = math.Vector3Max(maxVertex, rl.Vector3{ .x = self.vertices[i*3], .y = self.vertices[i*3 + 1], .z =  self.vertices[i*3 + 2] });
            }
        }

        // Create the bounding box
        var box: rl.BoundingBox = .{};
        box.min = minVertex;
        box.max = maxVertex;
        // std.debug.print("Min vertex: ({}, {}, {})\n", .{minVertex.x, minVertex.y, minVertex.z});
        // std.debug.print("Max vertex: ({}, {}, {})\n-------------------\n", .{maxVertex.x, maxVertex.y, maxVertex.z});

        return box;
    }

    fn deinit(self: *PlaceHolderMesh) void {
        // ASSUMES ALL FIELDS HAVE BEEN FILLED
        self.allocator.free(self.indices);
        self.allocator.free(self.vertices);
        self.allocator.free(self.normals);
        self.allocator.free(self.texcoords);
    }
};

fn checkDuplicateVerticesMT(vertices: [*c]f32, indices: []u32, uniqueVertex: [3]f32, uniqueVertexInd: u32, indiced: []bool, vertexCount: c_int) !void {
    const threadCount = MN.THREAD_COUNT;
    const VertexCount: usize = @intCast(vertexCount);
    
    const SpawnConfig = std.Thread.SpawnConfig;
    const memoryNeeded:usize = @intFromFloat(1.5*@as(f32, @floatFromInt(VertexCount*3*@bitSizeOf(f32) + indices.len*@bitSizeOf(u32) + uniqueVertex.len*@bitSizeOf(u32) + @bitSizeOf(u32) + indiced.len*@bitSizeOf(bool) + @bitSizeOf(c_int))));
    const threadConfig = SpawnConfig{.stack_size = memoryNeeded};


    const ThreadFuncArgs = struct {
        vertices: []f32,
        indices: []u32,
        startInd: usize,
        point: [3]f32,
        pointIndice: u32,
        indiced: []bool,
    };
    const verticeChunkSize:usize = @divFloor(VertexCount+threadCount-1, threadCount); // ceiling of division


    var threads: [threadCount]std.Thread = undefined;
    var i:usize = 0;
    while(i<threadCount):(i+=1){
        const verticeUpper:usize = verticeChunkSize*(i+1);
        const verticeChunkMax = if (verticeUpper < VertexCount) verticeUpper else VertexCount;

        const threadArgs = ThreadFuncArgs{
            .vertices = vertices[verticeChunkSize*i..verticeChunkMax],
            .indiced = indiced,
            .indices = indices,
            .point = uniqueVertex,
            .pointIndice = uniqueVertexInd,
            .startInd = verticeChunkSize*i,
        };

        threads[i] = try std.Thread.spawn(threadConfig, checkDuplicateVertices, .{threadArgs});
        errdefer threads[i].join();
    }

    for (&threads) | thread | thread.join(); // Wait for all threads to finish work

}

fn checkDuplicateVertices(context: anytype) void {
    // std.debug.print("Thread {} has started work...\n", .{std.Thread.getCurrentId()});
    const verticesStack: []f32  = context.vertices; // Send only a slice of the total vertex slice
    const indicesStack: []u32 = context.indices;
    const startInd: usize = context.startInd;
    // const stackSize: usize = context.stackSize;
    const point: [3]f32 = context.point;
    const pointIndice: u32 = context.pointIndice;
    const indiced: []bool = context.indiced;

    
    var j:usize = 0;

    while(j<@divExact(verticesStack.len,3)):(j+=1){
        if (indiced[j+startInd]) continue; // If already indiced->skip

        if (point[0] == verticesStack[j*3] and point[1] == verticesStack[j*3+1] and point[2] == verticesStack[j*3+2]) { // If point is the same
            indiced[j+startInd] = true; // Set point as being indiced

            indicesStack[j] = pointIndice; // Set indice to original unique-point
        } // Else check next point
    }
    // std.debug.print("Thread {} has finished work...\n", .{std.Thread.getCurrentId()});
}

// fn getBB(mesh: rl.Mesh) rl.BoundingBox {
// // Get min and max vertex to construct bounds (AABB)
//     var minVertex: rl.Vector3 = .{};
//     var maxVertex: rl.Vector3 = .{};

//     std.debug.print("flag6\n", .{});

//     if (mesh.vertexCount != 0)
//     {
//         // std.debug.print("Checking BoundingBox...\n", .{});
//     std.debug.print("flag7\n", .{});

//         minVertex = rl.Vector3{ .x = mesh.vertices[0], .y = mesh.vertices[1], .z = mesh.vertices[2] };
//         maxVertex = rl.Vector3{ .x = mesh.vertices[0], .y = mesh.vertices[1], .z = mesh.vertices[2] };
//         std.debug.print("flag8\n", .{});

//         var i:usize = 1;
//         while(i<mesh.vertexCount):(i+=1)
//         {
//             std.debug.print("flag9\n", .{});

//             // std.debug.print("Checked vertex {}: ({}, {}, {})\n", .{i, self.vertices[i*3], self.vertices[i*3+1], self.vertices[i*3+2]});
//             minVertex = math.Vector3Min(minVertex, rl.Vector3{ .x = mesh.vertices[i*3], .y = mesh.vertices[i*3 + 1], .z = mesh.vertices[i*3 + 2] });
//             maxVertex = math.Vector3Max(maxVertex, rl.Vector3{ .x = mesh.vertices[i*3], .y = mesh.vertices[i*3 + 1], .z =  mesh.vertices[i*3 + 2] });
//             std.debug.print("flag10\n", .{});

//         }
//     }
//     std.debug.print("flag11\n", .{});
//     // Create the bounding box
//     var box: rl.BoundingBox = .{};
//     box.min = minVertex;
//     box.max = maxVertex;
//     // std.debug.print("Min vertex: ({}, {}, {})\n", .{minVertex.x, minVertex.y, minVertex.z});
//     // std.debug.print("Max vertex: ({}, {}, {})\n-------------------\n", .{maxVertex.x, maxVertex.y, maxVertex.z});

//     return box;
// }