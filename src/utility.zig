const std = @import("std");
const rl = @cImport(@cInclude("raylib.h"));

const math = @import("math.zig");
const MN = @import("globals.zig");

const Allocator:type = std.mem.Allocator;

// Custom error definitions
const MeshError = error{
        NoFacesInMesh,
        InvalidDimensions,
        TooManyVertices,
        Unexpected,
    };

pub fn scaleMesh(mesh:*rl.Mesh, XScale: f32, YScale:f32, ZScale: f32) void {
    const vertexCount:usize = @intCast(mesh.vertexCount);
    
    const uniDir:bool = (XScale == YScale and XScale == ZScale); // Unidirectionally scalled

    var i:usize = 0; // Index of vertex
    while (i<vertexCount):(i+=1){
        // Vertex positions
        mesh.vertices[i*3] *= XScale;
        mesh.vertices[i*3+1] *= YScale;
        mesh.vertices[i*3+2] *= ZScale;

        // Vertex normals
        if (!uniDir){
            mesh.normals[i*3] /= XScale;
            mesh.normals[i*3+1] /= YScale;
            mesh.normals[i*3+2] /= ZScale;
            const magn = math.sqrt(mesh.normals[i*3]*mesh.normals[i*3] + mesh.normals[i*3+1]*mesh.normals[i*3+1] + mesh.normals[i*3+2]*mesh.normals[i*3+2]);
            mesh.normals[i*3] *= magn;
            mesh.normals[i*3+1] *= magn;
            mesh.normals[i*3+2] *= magn;
        }
    }
}

pub fn scaleMeshFromDImensions(mesh: *rl.Mesh, MapX: f32, MapY:f32, MapZ: f32) void {
    // Scale provided mesh to desired dimensions. If MapZ or MapY are 0, they will
    // be scaled according to MapX to maintain proportions.

    // ===== Measure current mesh dimensions =====
    const BBMesh = rl.GetMeshBoundingBox(mesh.*); // Get original map size and scale vectors to reach desired dimensions
    const BBMesh_size = math.vector3Subtract(BBMesh.max, BBMesh.min); // Assume min is all smaller dimensions

    // ===== Assert valid inputs =====
    if (MapX<=0) return MeshError.InvalidDimensions; // MapWidth must always be set

    // ===== Determine required scaling =====
    const XScale = MapX/BBMesh_size.x;
    const ZScale = if (MapZ<=0) XScale else MapZ/BBMesh_size.z;
    const YScale = if (MapY<=0) XScale else {
        const Ysize = if (BBMesh_size.y != 0) BBMesh_size.y else 1; // Avoid error in totally flat maps
        MapY/Ysize;
    };

    // ===== Scale mesh =====
    scaleMesh(mesh, XScale, YScale, ZScale);
}

pub fn addMeshIndicesHashed(allocator: Allocator, mesh: rl.Mesh) !PlaceHolderMesh {
    // Returns rl.Mesh as a PlaceHolderMesh for larger indice-range. Unloads provided mesh

    const VertexCount:usize = @intCast(mesh.vertexCount);
    const TriangleCount:usize = @intCast(mesh.triangleCount);
    
    // ===== Check whether mesh is indexed =====
    if (mesh.indices != null) {
        // Return same mesh as PlaceHolderMesh type
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

        rl.UnloadMesh(mesh);

        return result; 
    }
    // Else continue with de-duplicating vertices and indexing the mesh

    // ===== Assert that mesh can be indexed =====
    if (VertexCount>std.math.maxInt(u32)) return MeshError.TooManyVertices; // Could still be fine since vertexCount will decrease due to de-duplication
    
    // ===== Allocate memory to new (de-duped) arrays (Vertex, normals, texcoords, indices) =====
    const vertices = try allocator.alloc(f32, @intCast(VertexCount*3)); // Store trimmed list of vertices
    errdefer allocator.free(vertices);
    const normals = try allocator.alloc(f32, @intCast(VertexCount*3)); // Store trimmed list of normals
    errdefer allocator.free(normals);
    const UVs = try allocator.alloc(f32, @intCast(VertexCount*2)); // Store trimmed list of texCoords
    errdefer allocator.free(UVs);

    const indices = try allocator.alloc(u32, @intCast(TriangleCount*3)); // Stores indices to vertices
    errdefer allocator.free(indices);
    
    // ===== Start creating new mesh =====
    // ----- Initialize hashmap  -----
    var hashmap = std.hash_map.AutoHashMap([3]u32, u32).init(allocator); // Make hashmap with 'key' Vertex: ([3]f32->[3]u32) and 'value' index (u32) of unique-vertex
    try hashmap.ensureTotalCapacity(@intCast(VertexCount));

    // ----- Start iteration over non-unique vertices -----
    var i:u32 = 0; // Count of non-unique vertices
    var p:u32 = 0; // Counts number of unique vertices 
    while(i < VertexCount):(i+=1){
        if (i % 10000000 == 0) std.debug.print("Indiced {}/{} vertices\n", .{i, VertexCount});

        // ----- Store non-unique vertex as [3]u32 -----
        const vertice:[3]u32 = .{   @bitCast(mesh.vertices[i*3]),
                                    @bitCast(mesh.vertices[i*3+1]),
                                    @bitCast(mesh.vertices[i*3+2])}; // hashing f32 requires custom hashing scheme | casting to u32 assumes identical values for same-position vertices: No precision error, No -0.0/+0.0 or NaN shenanigans

        // ----- Check to-be-checked vertex with hashmap -----
        const getOrPutResults = hashmap.getOrPutAssumeCapacity(vertice); // place vertex in hashmap if non-existent
        
        if (!getOrPutResults.found_existing) { // vertex is unique
            // Store unique vertice, normals, texcoords, and indice
            const v0:f32 = @bitCast(vertice[0]);
            const v1:f32 = @bitCast(vertice[1]);
            const v2:f32 = @bitCast(vertice[2]);

            vertices[p*3] = v0;
            vertices[p*3+1] = v1;
            vertices[p*3+2] = v2;

            normals[p*3] = mesh.normals[i*3];
            normals[p*3+1] = mesh.normals[i*3+1];
            normals[p*3+2] = mesh.normals[i*3+2];

            UVs[p*2] = mesh.texcoords[i*2];
            UVs[p*2+1] = mesh.texcoords[i*2+1];

            indices[i] = p;
            
            // Store pointer to self
            getOrPutResults.value_ptr.* = p;
            p +=1; // Increase count of unique vertices

        } else { // If vertice already exists
            indices[i] = getOrPutResults.value_ptr.*; // Reference unique vertex
        }
    }

    // ===== Construct newly indiced mesh =====
    const vertexCount = p; // New vertex count

    // ----- Memory management -----
    // Trim memory
    const vertices_ = try allocator.alloc(f32, vertexCount*3); // (p1 = Number of unique vertices)*3 = xyz
    errdefer allocator.free(vertices_);

    const normals_ = try allocator.alloc(f32, vertexCount*3); // (p1 = Number of unique vertices)*3 = xyz
    errdefer allocator.free(normals_);

    const UVs_ = try allocator.alloc(f32, vertexCount*2); // (p1 = Number of unique vertices)*3 = xyz
    errdefer allocator.free(UVs_);

    // Transfer values to trimmed memory
    std.mem.copyForwards(f32, vertices_, vertices[0..vertexCount*3]);
    std.mem.copyForwards(f32, normals_, normals[0..vertexCount*3]);
    std.mem.copyForwards(f32, UVs_, UVs[0..vertexCount*2]);
    
    // Free memory
    hashmap.deinit();
    allocator.free(vertices);
    allocator.free(normals);
    allocator.free(UVs);

    // ----- Construct indiced Mesh -----
    var result = PlaceHolderMesh{.allocator = allocator};
    result.indices = indices;
    result.vertices = vertices_;
    result.texcoords = UVs_;
    result.normals = normals_;
    result.vertexCount = @intCast(vertexCount);
    result.triangleCount = @intCast(TriangleCount);

    return result;
}

pub fn chunkMesh(allocator: Allocator, mesh: PlaceHolderMesh, XChunks: usize, ZChunks: usize) ![]rl.Mesh {
    // Splits mesh into slice of meshes according to specified amount of chunks

    // ===== Creat constants in variant types =====
    const meshBB = mesh.getBoundingBox();
    const sizeBB = math.vector3Subtract(meshBB.max, meshBB.min);

    const totChunks: usize = XChunks*ZChunks;
    const f32_XChunks:f32 = @floatFromInt(XChunks);
    const f32_ZChunks:f32 = @floatFromInt(ZChunks);
    const ChunkXSize: f32 = sizeBB.x/f32_XChunks;
    const ChunkZSize: f32 = sizeBB.z/f32_ZChunks;

    // ===== Assert feasibility of creating chunks =====
    if (@divFloor(mesh.vertexCount, @as(c_int, @intCast(XChunks*ZChunks))) > std.math.maxInt(c_ushort)) {
        std.debug.print("Vertices expected to be in each chunk out of maximum: {}/{}\n ", .{@divFloor(mesh.vertexCount, @as(c_int, @intCast(XChunks*ZChunks))), std.math.maxInt(c_ushort)});
        return MeshError.TooManyVertices;
    }


    // ===== Start Mesh array =====
    var meshes = try allocator.alloc(PlaceHolderMesh, totChunks);
    errdefer allocator.free(meshes);
    meshes[0] = mesh; // Store value inside array


    // ===== Start splitting meshes =====
    // ----- Split mesh allong x axis into strips -----
    var z:usize = 0;
    while (z<ZChunks-1):(z+=1){
        std.debug.print("Coordinate: (0, 0, {})\n", .{@as(f32, @floatFromInt(z+1))*ChunkZSize + meshBB.min.z});

        const splitmeshes = try splitMesh(allocator, meshes[z*XChunks], rl.Vector3{.z = @as(f32, @floatFromInt(z+1))*ChunkZSize + meshBB.min.z}, rl.Vector3{.x = 1});
        errdefer for (splitmeshes) | splitmesh | splitmesh.deinit();

        meshes[z*XChunks].deinit(); // Free memory of combined mesh
        meshes[z*XChunks] = splitmeshes[0]; // Store seperated slice in first spot
        meshes[(z+1)*XChunks] = splitmeshes[1]; // Store remaining bulk in next spot
        allocator.free(splitmeshes); // Free memory of container
    }

    // ----- Split mesh-strips along z axis into chunks -----
    z = 0;
    while(z<ZChunks):(z+=1){ // z = strip nr.
        var x:usize = 0;
        while(x<XChunks-1):(x+=1){ // x = cut nr.
            std.debug.print("Coordinate: ({}, 0, 0)\n", .{@as(f32, @floatFromInt(x+1))*ChunkXSize + meshBB.min.x}); 

            const splitmeshes = try splitMesh(allocator, meshes[z*XChunks + x], rl.Vector3{.x = @as(f32, @floatFromInt(x+1))*ChunkXSize + meshBB.min.x}, rl.Vector3{.z = -1});
            errdefer for (splitmeshes) | splitmesh | splitmesh.deinit();

            meshes[z*XChunks+x].deinit();
            meshes[z*XChunks+x] = splitmeshes[0];
            meshes[z*XChunks+x+1] = splitmeshes[1];
            allocator.free(splitmeshes);
        }
    }

    // ===== Convert all meshes to rl.Mesh and return =====
    const results = try allocator.alloc(rl.Mesh, totChunks);
    errdefer allocator.free(results);

    var i:usize = 0;
    while(i<meshes.len):(i+=1){
        results[i] = try meshes[i].mesh2RL();
        errdefer freeMesh(allocator, results[i]);
    }
    
    allocator.free(meshes);

    return results;
}

fn splitMesh(allocator: Allocator, mesh: PlaceHolderMesh, point: rl.Vector3, dir: rl.Vector3) ![]PlaceHolderMesh {
    // Splits mesh into 2, does NOT deinitialize provided mesh
    // 
    //
    //
    // Just don't look at the source code

    const TotVertexCount: u32 = @intCast(mesh.vertexCount);
    const TotTriangleCount: u32 = @intCast(mesh.triangleCount);

    const orth_dir = math.vector3CrossProduct(rl.Vector3{.y = 1}, dir);

    // Continue initializing vertices
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

    // Bounding box variable to keep track of
    var BBmin1:rl.Vector3 = rl.Vector3{.x = 999999.9, .y = 999999.9, .z = 999999.9};
    var BBmax1:rl.Vector3 = rl.Vector3{.x = -999999.9, .y = -999999.9, .z = -999999.9};
    var BBmin2:rl.Vector3 = rl.Vector3{.x = 999999.9, .y = 999999.9, .z = 999999.9};
    var BBmax2:rl.Vector3 = rl.Vector3{.x = -999999.9, .y = -999999.9, .z = -999999.9};

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
            
            BBmin1 = math.Vector3Min(BBmin1, rl.Vector3{.x = vertice1[p1*3], .y = vertice1[p1*3+1],.z = vertice1[p1*3+2]});
            BBmax1 = math.Vector3Max(BBmax1, rl.Vector3{.x = vertice1[p1*3], .y = vertice1[p1*3+1],.z = vertice1[p1*3+2]});

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
            
            BBmin2 = math.Vector3Min(BBmin2, rl.Vector3{.x = vertice2[p2*3], .y = vertice2[p2*3+1],.z = vertice2[p2*3+2]});
            BBmax2 = math.Vector3Max(BBmax2, rl.Vector3{.x = vertice2[p2*3], .y = vertice2[p2*3+1],.z = vertice2[p2*3+2]});

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

                // Check added vertice for boundingbox
                BBmin1 = math.Vector3Min(BBmin1, rl.Vector3{.x = vertice1[(chunk1Vertices + added_vertices1)*3], .y = vertice1[(chunk1Vertices + added_vertices1)*3+1],.z = vertice1[(chunk1Vertices + added_vertices1)*3+2]});
                BBmax1 = math.Vector3Max(BBmax1, rl.Vector3{.x = vertice1[(chunk1Vertices + added_vertices1)*3], .y = vertice1[(chunk1Vertices + added_vertices1)*3+1],.z = vertice1[(chunk1Vertices + added_vertices1)*3+2]});

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
                vertice2[(chunk2Vertices + added_vertices2)*3] = vertice1[indexOfOtherInVertex1*3]; // @as(usize, @intCast(
                vertice2[(chunk2Vertices + added_vertices2)*3+1] = vertice1[indexOfOtherInVertex1*3+1];
                vertice2[(chunk2Vertices + added_vertices2)*3+2] = vertice1[indexOfOtherInVertex1*3+2];

                // Check added vertice for boundingbox
                BBmin2 = math.Vector3Min(BBmin2, rl.Vector3{.x = vertice2[(chunk2Vertices + added_vertices2)*3], .y = vertice2[(chunk2Vertices + added_vertices2)*3+1],.z = vertice2[(chunk2Vertices + added_vertices2)*3+2]});
                BBmax2 = math.Vector3Max(BBmax2, rl.Vector3{.x = vertice2[(chunk2Vertices + added_vertices2)*3], .y = vertice2[(chunk2Vertices + added_vertices2)*3+1],.z = vertice2[(chunk2Vertices + added_vertices2)*3+2]});
                
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
        return MeshError.NoFacesInMesh;
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
    meshes[0].boundingBox = rl.BoundingBox{.min = BBmin1, .max = BBmax1};

    meshes[1] = PlaceHolderMesh{.allocator = allocator};
    meshes[1].triangleCount = @intCast(p2);
    meshes[1].indices = indices2;
    meshes[1].vertexCount = @intCast(chunk2_Vertices);
    meshes[1].vertices = vertices2;
    meshes[1].texcoords = UVs2;
    meshes[1].normals = normals2;
    meshes[1].boundingBox = rl.BoundingBox{.min = BBmin2, .max = BBmax2};

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

pub fn freeMesh(allocator: Allocator, mesh: rl.Mesh) void {
    // Deinitialized manually constructed meshes

    const indices: []c_ushort = mesh.indices[0..@as(usize, @intCast(mesh.triangleCount))*3];
    const vertices: []f32 = mesh.vertices[0..@as(usize, @intCast(mesh.vertexCount))*3];
    const normals: []f32 = mesh.normals[0..@as(usize, @intCast(mesh.vertexCount))*3];
    const UVs: []f32 = mesh.texcoords[0..@as(usize, @intCast(mesh.vertexCount))*2];

    allocator.free(indices);
    allocator.free(vertices);
    allocator.free(normals);
    allocator.free(UVs);
}

pub fn moveMesh(mesh: anytype, dist: rl.Vector3) void {
    // Alters mesh vertices dist from original spot
    var i:usize = 0;
    while(i<mesh.vertexCount):(i+=1){
        mesh.vertices[i*3] += dist.x;
        mesh.vertices[i*3+1] += dist.y;
        mesh.vertices[i*3+2] += dist.z;
    }
}

pub fn moveChunks(meshes: anytype, positions: []rl.Vector3) void {
    // Moves all meshes -positions in place
    var i:usize = 0;
    while (i < meshes.len):(i+=1) {
        moveMesh(&meshes[i], math.vector3Inverse(positions[i]));
    }
}

// Auxilirary functions
fn find3bool(list: [3]bool, boolean: bool) u2 {
    // Return first indice in which list[i] == boolean
    var i:usize = 0;
    while(i<list.len):(i+=1){
        if (list[i] == boolean) return @intCast(i);
    }
    return @intCast(i); // If nothing can be found return i -> Out of bounds error if used
}

// Auxilirary structs
pub const PlaceHolderMesh = struct {
    // Useful to store large amount of indices as it uses u32 instead of u16 
    allocator: Allocator,
    indices: []u32 = undefined,
    vertices: []f32 = undefined,
    normals: []f32 = undefined,
    texcoords: []f32 = undefined,
    triangleCount: c_int = undefined,
    vertexCount: c_int = undefined,
    boundingBox: rl.BoundingBox = undefined,

    fn getBoundingBox(self: PlaceHolderMesh) rl.BoundingBox{
        // Get min and max vertex to construct bounds (AABB)
        var minVertex: rl.Vector3 = .{};
        var maxVertex: rl.Vector3 = .{};

        if (self.vertices.len != 0)
        {
            minVertex = rl.Vector3{ .x = self.vertices[0], .y = self.vertices[1], .z = self.vertices[2] };
            maxVertex = rl.Vector3{ .x = self.vertices[0], .y = self.vertices[1], .z = self.vertices[2] };

            var i:usize = 1;
            while(i<self.vertexCount):(i+=1)
            {
                minVertex = math.Vector3Min(minVertex, rl.Vector3{ .x = self.vertices[i*3], .y = self.vertices[i*3 + 1], .z = self.vertices[i*3 + 2] });
                maxVertex = math.Vector3Max(maxVertex, rl.Vector3{ .x = self.vertices[i*3], .y = self.vertices[i*3 + 1], .z =  self.vertices[i*3 + 2] });
            }
        }

        // Create the bounding box
        var box: rl.BoundingBox = .{};
        box.min = minVertex;
        box.max = maxVertex;

        return box;
    }

    fn mesh2RL(self: *PlaceHolderMesh) !rl.Mesh {
        // Returns a rl.Mesh type, deinits self
        // DOES NOT UPLOAD MESH

        // ----- Initialize indice array of type c_ushort instead of u32 -----
        const indices = try self.allocator.alloc(c_ushort, self.indices.len);
        errdefer self.allocator.free(indices);
        
        var j:usize = 0;
        while(j < indices.len):(j+=1) indices[j] = @intCast(self.indices[j]); // copy indice values
        self.allocator.free(self.indices);
        

        // ----- Create rl.Mesh to upload and return -----
        var mesh = rl.Mesh{};
        mesh.triangleCount = self.triangleCount;
        mesh.vertexCount = self.vertexCount;

        mesh.indices = indices.ptr;
        mesh.vertices = self.vertices.ptr;
        mesh.normals = self.normals.ptr;
        mesh.texcoords = self.texcoords.ptr;
        
        return mesh;
    }

    fn deinit(self: *PlaceHolderMesh) void {
        // ASSUMES ALL FIELDS HAVE BEEN FILLED
        self.allocator.free(self.indices);
        self.allocator.free(self.vertices);
        self.allocator.free(self.normals);
        self.allocator.free(self.texcoords);
    }
};