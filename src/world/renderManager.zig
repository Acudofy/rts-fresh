// mapManager.zig
const std = @import("std");
const rl = @cImport(@cInclude("raylib.h"));

const MN = @import("../globals.zig");

const Map = @import("map.zig").Map;
const Camera = @import("cameraController.zig").MainCamera;

// pub const RenderManager = struct {
//     map: Map,
//     allocator: std.mem.Allocator,
//     debug_mode: bool = false,

//     pub fn init( allocator: std.mem.Allocator, height: f32, width: f32, length: f32, heightmap_path: []const u8, chunks_x: usize, chunks_y: usize) !RenderManager {
//         const map = try Map.init(
//             allocator,
//             height,
//             width,
//             length,
//             heightmap_path,
//             chunks_x,
//             chunks_y
//         );

//         return RenderManager{
//             .map = map,
//             .allocator = allocator,
//         };
//     }

//     pub fn deinit(self: *RenderManager) void {
//         self.map.deinit();
//     }

//     pub fn draw(self: *const RenderManager) void {
//         if (self.debug_mode) {
//             self.drawDebug();
//         } else {
//             self.drawNormal();
//         }
//     }

//     fn drawDebug(self: *const RenderManager) void {
//         // Draw with debug colors (your original drawing code)
//         for (self.map.models, self.map.positions, 0..) |model, position, i| {
//             const color = COLORS[@mod(i, COLORS.len)];
//             rl.DrawModel(model, position, 1.0, color);
//             rl.DrawBoundingBox(self.map.boundingBoxes[i], rl.GREEN);
//         }
//     }

//     fn drawNormal(self: *const RenderManager) void {
//         for (self.map.models, self.map.positions) |model, position| {
//             rl.DrawModel(model, position, 1.0, rl.WHITE);
//         }
//     }

//     pub fn setDebugMode(self: *RenderManager, enabled: bool) void {
//         self.debug_mode = enabled;
//     }
// };

// Start struct
pub const RenderManager = struct {
    map: Map,
    camera: *rl.Camera3D,
    allocator: std.mem.Allocator,
    _screenPos: [MN.N_CHUNKS]rl.Vector2 = undefined,
    _CoreInd:    [MN.N_CHUNKS]bool = undefined, // Stores indices of chunks with positions within screen window
    _VisibleInd: [MN.N_CHUNKS]bool = undefined, // Stores indices of chunks needed to be rendered
    _MonitorInd: [MN.N_CHUNKS]bool = [_]bool{true} ** MN.N_CHUNKS, // Stores indices of chunks likely to change visibility state
    _RenderMargin: f32 = MN.CHUNK_SCREENMARGIN,

    // Define errors
    const MapError = error{
        ValueOutOfBounds,
    };

    pub fn init(allocator: std.mem.Allocator, height: f32, width: f32, length: f32, heightmap_path: []const u8, chunks_x: usize, chunks_y: usize, cam: *rl.Camera3D) !RenderManager {
        const map = try Map.init(
            allocator,
            height,
            width,
            length,
            heightmap_path,
            chunks_x,
            chunks_y
        );
        var m = RenderManager{ 
            .map = map, 
            .camera = cam,
            .allocator = allocator
            };

        m.updateScreenPos(true);

        return m;
    }

    pub fn deinit(self: RenderManager) void {
        self.map.deinit();
    }

    pub fn getIdFromCoord(self: *RenderManager, Coord: rl.Vector2) !usize {
        const rowlen = self.map.chunks_x;
        const chunkWidth = self.map.chunk_width;
        const chunkHeight = self.map.chunk_height;

        if (Coord.x < 0 or Coord.x > MN.MAP_WIDTH or Coord.y < 0 or Coord.y > MN.MAP_HEIGHT) {
            return MapError.ValueOutOfBounds;
        }

        const X_pos: usize = @intFromFloat(Coord.x / chunkWidth); // X coordinate in chunks between 0-rowlen
        const Y_pos: usize = @intFromFloat(Coord.y / chunkHeight); // Y coordinate in chunks

        return X_pos + Y_pos*rowlen; // Return id of chunk
    }

    pub fn getVisible(self: *RenderManager) []bool {
        return self._VisibleInd[0..];
    }

    fn updateScreenPos(self: *RenderManager, refresh: bool) void {
        var ScreenPositions: [MN.N_CHUNKS]rl.Vector2 = undefined;
        const cam = self.camera;
        const monitored = self._MonitorInd;
        const chunkPos = self.map.positions;

        var i:usize = 0;

        while(i < monitored.len):(i+=1){
            if (monitored[i] or refresh){
                ScreenPositions[i] = rl.GetWorldToScreen(chunkPos[i], cam.*);
            }
        }
        self._screenPos = ScreenPositions;
        self.setMonitored(refresh);
    }


    fn setMonitored(self: *RenderManager, refresh: bool) void {
        // Update chunks to be displayed and monitored
        const nChunks = MN.N_CHUNKS;
        if (refresh) {
            self._VisibleInd = [_]bool{false} ** self._VisibleInd.len; // Reset visibleInd array
            self._MonitorInd = self._VisibleInd;
            self._CoreInd = self._VisibleInd;
        }

        var i:usize = 0;
        var W2S: rl.Vector2 = undefined;
        while (i < self._MonitorInd.len):(i+=1) {
            var delInd:usize = 1; // Auxilirary variable for removing unseen chunks from self._visibleInd
            var foundInd:usize = nChunks+9; // Auxilirary variable for managing adjacent chunks to removed chunk
            
            if (self._MonitorInd[i] or refresh) { // If scheduled for monitoring (check) or chunk-refresh is set to true
                W2S = self._screenPos[i]; // World to Screen position
                if (W2S.x >= -self._RenderMargin and W2S.y >= -self._RenderMargin and W2S.x < MN.SCREEN_WIDTH + self._RenderMargin and W2S.y < MN.SCREEN_HEIGHT + self._RenderMargin) { // If chunk is on-screen
                    // If core -> Nothing happens
                    // If refresh -> Select as core chunk
                    // If monitored & !core -> Chunk became visible i.e. add adjacent chunks to monitoring & visible and add self to core
                    if (refresh){
                        self._CoreInd[i] = true; // Note that chunk-center is visible on screen
                    }
                    if (self._MonitorInd[i] and !self._CoreInd[i]) {
                        self._CoreInd[i] = true; // Add self to core
                        const neighbours = findNeighbours(i, true); // Find neighbours to monitor
                        for (0..neighbours.exists.len) | p | {
                            self.setVisible(neighbours.loc, neighbours.exists, p, true);
                        }
                    }
                } else {
                // If core & !visible -> Remove self from core, remove soley monitored chunks from monitored if shared neighbour is not a core-chunk
                    if (self._CoreInd[i]) { // If not seen but recorded as core chunk
                        self._CoreInd[i] = false; // Remove core-status

                        const delCoord = ChunkCoord(i);
                        const BiasDir = MN.CHUNKBIAS;

                        const neighbours = findNeighbours(i, false); // Find neighbours to update

                        var ind:usize = 0; // Used to control while loop
                        var wind:usize = 0; // Used to store 'wrapped ind' 
                        var core:[neighbours.exists.len]bool = undefined;
                        while (ind < 8+1):(ind+=1) { // Loop trough all neighbours and repeat first ind by using @mod(ind, 8)
                            // Go trough all neighbours and check if they are core chunks -> find edged by getting pointers to _CoreInd and perform XOR -> if [0] = true -> move first edge ind 1 closer: if false -> move second ind 1 closer
                            wind = @mod(ind,8);
                            if (neighbours.exists[wind]){ // NOTE: double allocation to [0] at ind == 0 or ind == 8 
                                core[wind] = self._CoreInd[neighbours.loc[wind]]; // Set core to core-status of surrounding chunks 
                            } else { // If neighbour does not exist
                                core[wind] = false; // assume it to not be a core chunk
                            }
                            if (ind > 0){
                                if (core[wind] != core[ind-1]){ // If core-status change
                                    if (core[ind-1]) { // if previous was core
                                        const edgeCoords = ChunkCoord(neighbours.loc[ind-1]); // Previous ind points to core chunk
                                        if (@mod(ind-1, 2) == 1) { // If core chunk is directly-adjacent

                                            self.setVisible(neighbours.loc, neighbours.exists, wind, true);
                                            self.setVisible(neighbours.loc, neighbours.exists, @mod(ind+1, 8), 
                                            if (@mod(MN.CHUNKBIASDIR,4)==0)  !(delCoord.y-edgeCoords.y-BiasDir.y == 0) else !(delCoord.x-edgeCoords.x-BiasDir.x == 0)); // Condition for bias to be relevant, if so-> set second chunk to false i.e. !Biascondition | BIAS NEEDS TO BE DIAGONAL -> OTHERWISE CONDITION OF DIRECT ADJACENCY MIGHT NOT BE FULLFILLED
                                        } else {
                                            self.setVisible(neighbours.loc, neighbours.exists, wind, true);
                                            self.setVisible(neighbours.loc, neighbours.exists, @mod(ind+1,8), false);
                                        }
                                        if (foundInd == nChunks+9){ // If first change
                                            foundInd = ind-1; // Set location of core chunk
                                        } else{
                                            while (delInd<=3-((ind-1)-foundInd)):(delInd+=1){
                                                self.setVisible(neighbours.loc, neighbours.exists, @mod(ind-1+2+delInd, 8), false);
                                            }
                                        }
                                    } else{ // If previous was not a core

                                        const edgeCoords = ChunkCoord(neighbours.loc[wind]); // ind points to core chunk
                                        if (@mod(ind, 2) == 1){
                                            self.setVisible(neighbours.loc, neighbours.exists, ind-1, true);
                                            self.setVisible(neighbours.loc, neighbours.exists, @mod(ind+8-2,8), 
                                                if (@mod(MN.CHUNKBIASDIR,4)==0) !(delCoord.x-edgeCoords.x-BiasDir.x == 0) else !(delCoord.y-edgeCoords.y-BiasDir.y == 0));
                                        }else{
                                            self.setVisible(neighbours.loc, neighbours.exists, ind-1, true);
                                            self.setVisible(neighbours.loc, neighbours.exists, @mod(ind+8-2,8), false);
                                        }
                                        
                                        if (foundInd == nChunks+9){ // If first change
                                            foundInd = ind; // Set location of core chunk
                                        }else{ // else fill in all unfound chunks as non-visible
                                            while(delInd <= 3-(foundInd+8-ind)):(delInd+=1){
                                                self.setVisible(neighbours.loc, neighbours.exists, ind-2-delInd, false);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                
                    }
                }
            }
        }

        i = 0;
        if (refresh){ // If chunks are being refreshed
            // Make all chunks neighbouring the core chunks rendered and monitored
            // Posible todo: Make 'land-locked' core chunks not be monitored 
            while (i<self._CoreInd.len):(i+=1) {
                if (self._CoreInd[i]) { // If chunk is visible on screen
                // All neighbours except bias direction need to be rendered i.e. all except (+y bias + x bias)
                    self._VisibleInd[i] = true;
                    const neighbours = findNeighbours(i, true);
                    var ind:usize = 0;
                    while (ind < neighbours.exists.len):(ind+=1){
                        self.setVisible(neighbours.loc, neighbours.exists, ind, true);
                    }
                }
            }
        }
        self._MonitorInd = self._VisibleInd; // Include all rendered chunks in list of to-be monitored chunks
    }

    fn printmapVar(self: *RenderManager) void {
        var i:usize = 0;
        const variable = self._screenPos;
        const rowlen = MN.X_CHUNKS;
        const nChunks = MN.N_CHUNKS; 
        while (i < nChunks):(i+=1){
            if (@mod(i, rowlen) == 0){
                std.debug.print(" |\n", .{});
            }
            std.debug.print("| ({}, {})", .{@round(variable[i].x), @round(variable[i].y)});
        }
        std.debug.print(" |\n", .{});
    }

    pub fn setVisible(self: *RenderManager, neighbourLoc: [8]usize, neighbourExist: [8]bool, i: usize, val: bool) void {
        // Change self._visibleInd at the index of the i-th neighbour to val if it exists.
        if (neighbourExist[i]) { // If neighbour exists and is not in bias direction
            self._VisibleInd[neighbourLoc[i]] = val;
        }
    }

    pub fn update(self:*RenderManager) void {
        self.updateScreenPos(false);
    }

    pub fn draw(self: *RenderManager) void {
        const chunk_pos = self.map.positions;
        const visible = self._VisibleInd;

        var i:usize = 0;
        while (i<self._screenPos.len):(i+=1){
            if (visible[i]){
                rl.DrawModel(self.map.models[i], chunk_pos[i], 1.0, rl.RED);
                if(self._CoreInd[i]){
                    rl.DrawBoundingBox(self.map.boundingBoxes[i], rl.GREEN);
                }
            }
        }
    }
    
    fn findNeighbours(i: usize, excludeBias: bool) struct {loc: [8]usize, exists: [8]bool} {
        // indices follow spiral patern from top left clockwise, gives null if no neighbour is found
        // find indices of chunks neighbouring to chunk[i]

        // Load constants from magic numbers relevant to chunks
        const rowLen:c_int = @intCast(MN.X_CHUNKS);
        const nChunks:usize = @intCast(MN.N_CHUNKS);

        const neighbours: [8]usize = if (i >= rowLen+1)
            [8]usize{i-rowLen-1, i-rowLen, i-rowLen+1, i+1, i+rowLen+1, i+rowLen, i+rowLen-1, i-1}
        else if (i >= rowLen)
            [8]usize{nChunks, i-rowLen, i-rowLen+1, i+1, i+rowLen+1, i+rowLen, i+rowLen-1, i-1}
        else if (i > 0)
            [8]usize{nChunks, nChunks, nChunks, i+1, i+rowLen+1, i+rowLen, i+rowLen-1, i-1}
        else
            [8]usize{nChunks, nChunks, nChunks, i+1, i+rowLen+1, i+rowLen, i+rowLen-1, nChunks}; // Prevent underflow of usize

        const BiasDir = MN.CHUNKBIASDIR;
        var _exists:[8]bool = undefined;
        var ind:usize = 0;
        
        // Edge case: only 1 chunk in each row (along x axis)
        if(rowLen == 1) {
            _exists[0] = false;
            _exists[1] = i>0; // If not top chunk
            _exists[2] = false;
            _exists[3] = false;
            _exists[4] = false;
            _exists[5] = i < nChunks-1; // If not bottom chunk
            _exists[6] = false;
            _exists[7] = false;
        } else{ // Actually check neighbours
            const b = @rem(i, rowLen); // chunk position along x axis
            while (ind < _exists.len):(ind+=1){
                const a:usize = @rem(neighbours[ind], rowLen); // chunk position along x of neighbour
                const diffcheck:bool = if (a >= b) (a-b)<=1 else (b-a) == 1;
                _exists[ind] = neighbours[ind] >= 0 and neighbours[ind] < nChunks and diffcheck and !(excludeBias and ind == BiasDir);
            }
        }
        const exists:[8]bool = _exists;

        return .{.loc = neighbours, .exists = exists};
    }
};

fn ChunkCoord(ind:usize) struct{x:c_int, y:c_int} {
    const rowlen = MN.X_CHUNKS;
    return .{.x = @as(c_int, @intCast(@mod(ind, rowlen))), .y = @as(c_int, @intCast(@divFloor(ind, rowlen)))}; 
}


// DEBUG COLORSSS
const COLORS = [_]rl.Color{
    rl.RED,
    rl.GREEN,
    rl.BLUE,
    rl.YELLOW,
    rl.PURPLE,
    rl.ORANGE,
    rl.PINK,
    rl.MAROON,
    rl.LIME,
    rl.SKYBLUE,
};