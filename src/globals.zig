const std = @import("std");
const rl = @cImport(@cInclude("raylib.h"));

pub const MapTextureLoc = "assets/images/Map.png";

pub const MAP_HIGHDETAIL_HM = "assets/images/HM2903_2903.png";
pub const HM_LOCATION = "assets/images/HM201_201.png"; // Height map

pub const MAP_MODEL_LOCATION = "assets/models/Dune/lowresmodel.obj";
pub const MAP_TEXTURE_LOCATION = "assets/models/Dune/colormap.png";

pub const TEST_TEXTURE_LOCATION = "assets/images/Texture2_2.png";

// pub const HM_LOCATION = "assets/images/HM2903_2903.png"; // Height map
pub const MAP_WIDTH = 100; // [m]
pub const MAP_HEIGHT = 100; // [m]
pub const MAP_HEIGHT_Z = 20; // [m] for max value (255?)
pub const MAP_DIM = rl.Vector3{ .x = MAP_WIDTH, .y = MAP_HEIGHT, .z = MAP_HEIGHT_Z };
// pub const MAP_RES = 2; // [vertices/m]
pub const X_CHUNKS = 1; // Chunks for width
pub const Y_CHUNKS = 2; // Chunks in height-direction
pub const N_CHUNKS: c_int = X_CHUNKS * Y_CHUNKS; // Total Chunks
pub const CHUNKBIAS: struct{x:c_int, y:c_int} = .{.x = 1, .y = 1}; // NOTE: ALWAYS HAS TO BE A CORNER | Direction opposite to the location of the center in the mesh i.e. center of mesh is positive x & y: bias is negative x & y -> (-1, -1)
pub const CHUNKBIASDIR: usize = 4; // Direction used by neighbour function in MapManager | determined based on clockwise spiral in 3x3 grid from topleft from 0.  
pub const CHUNK_SCREENMARGIN: f32 = 160.0;

pub const SCREEN_WIDTH = 1500;
pub const SCREEN_HEIGHT = 900;
pub const SCREEN_FPS = 144;

// Gameplay
pub const MAX_ENTITIES: usize = 255;
pub const PATHING_DEADZONE: f32 = 0.5;

// Controls
pub const MOUSE_DEADZONE= std.math.pow(f32, 20.0, 2); // Distance-squared (=d^2) within which mouse will not be considered moving

// types
pub const Player = enum {PLAYER1, PLAYER2, PLAYER3, PLAYER4};

// Computations
pub const THREAD_COUNT: usize = 4;
pub const f32Precision: f32 = std.math.pow(f32, 10.0, -7.0); // numbers after decimal