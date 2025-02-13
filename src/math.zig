const rl = @cImport(@cInclude("raylib.h"));

pub fn vector3Subtract(v1: rl.Vector3, v2: rl.Vector3) rl.Vector3 {
    return rl.Vector3{
        .x = v1.x - v2.x,
        .y = v1.y - v2.y,
        .z = v1.z - v2.z,
    };
}

pub fn vector3Add(v1: rl.Vector3, v2: rl.Vector3) rl.Vector3 {
    return rl.Vector3{
        .x = v1.x + v2.x,
        .y = v1.y + v2.y,
        .z = v1.z + v2.z,
    };
}

pub fn vector3Scale(vec: rl.Vector3, scale: f32) rl.Vector3 {
    return .{.x = vec.x*scale, .y = vec.y*scale, .z = vec.z*scale};
}

pub fn vectorDistanceSquared(v1: rl.Vector2, v2: rl.Vector2) f32 {
    return (v1.x-v2.x)*(v1.x-v2.x) + (v1.y-v2.y)*(v1.x-v2.x);
}

pub fn vector3Magnitude(v: rl.Vector3) f32 {
    return  @sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
}

pub fn vector3Normalize(v: rl.Vector3) rl.Vector3 {
    const magnitude = @sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (magnitude == 0) {
        return rl.Vector3{ .x = 0, .y = 0, .z = 0 }; // Handle zero vector case
    }
    return rl.Vector3{
        .x = v.x / magnitude,
        .y = v.y / magnitude,
        .z = v.z / magnitude,
    };
}

pub fn vector2Normalize(v: rl.Vector2) rl.Vector2 {
    const magnitude = @sqrt(v.x * v.x + v.y * v.y);
    if (magnitude == 0) {
        return rl.Vector2{ .x = 0, .y = 0}; // Handle zero vector case
    }
    return rl.Vector2{
        .x = v.x / magnitude,
        .y = v.y / magnitude,
    };
}

pub fn vector3CrossProduct(v1: rl.Vector3, v2: rl.Vector3) rl.Vector3 {
    return rl.Vector3{
        .x = v1.y * v2.z - v1.z * v2.y,
        .y = v1.z * v2.x - v1.x * v2.z,
        .z = v1.x * v2.y - v1.y * v2.x,
    };
}

pub fn vector3DotProduct(v1: rl.Vector3, v2: rl.Vector3) f32 {
    return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z;
}

pub fn translateMatrix(v: rl.Vector3) rl.Matrix {
    return rl.Matrix{   .m0 = 1.0, .m5 = 1.0, .m10 = 1.0, // follows conventions from https://www.gamedevpensieve.com/math/math_transforms 
                        .m12 = v.x, .m13 = v.y, 
                        .m14 = v.z, .m15 = 1.0}; 
}

pub fn matrixAddTranslate(M: rl.Matrix, v: rl.Vector3) rl.Matrix {
    var result: rl.Matrix = M; 
    result.m12 = v.x;
    result.m13 = v.y;
    result.m14 = v.z;
    return result;
    // {.m12 = v.x, .m13 = v.y, .m14 = v.z};
    // M.m13 = v.y;

}

pub fn rotationFromNormalForwardAndTranslation(normal: rl.Vector3, forward: rl.Vector3, transform: rl.Vector3) rl.Matrix {
    // X is assumed to be forward in the model 
    const y_new = vector3Normalize(normal);
    const vf = vector3Normalize(forward);

    const z_new = vector3CrossProduct(vf, y_new);
    const x_new = vector3CrossProduct(y_new, z_new);

    return rl.Matrix{
        .m0 = x_new.x, .m1 = x_new.y, .m2 = x_new.z,
        .m4 = y_new.x, .m5 = y_new.y, .m6 = y_new.z,
        .m8 = z_new.x, .m9 = z_new.y, .m10 = z_new.z,
        .m12 = transform.x, .m13 = transform.y, .m14 = transform.z, .m15 = 1 
    };
}

pub fn rotateVecAroundY(vec: rl.Vector3, ang: f32) rl.Vector3 {
    return .{   .x = vec.x*@cos(ang) - vec.z*@sin(ang),
                .z = vec.x*@sin(ang) + vec.z*@cos(ang)};
}

pub fn transformBoundingBox(BB: rl.BoundingBox, transform: rl.Matrix) rl.BoundingBox {
    //If BB is to be rotated: will return an oversize bounding box to remain axis-oriented
    return rl.BoundingBox{  .min = vector3MatrixProduct(BB.min, transform),
                            .max = vector3MatrixProduct(BB.max, transform)};
    
    // var min_v4: rl.Vector3 = .{.x = BB.min.x, .y = BB.min.y, .z = BB.min.z, .w = 1};
    // var max_v4: rl.Vector4 = .{.x = BB.max.x, .y = BB.max.y, .z = BB.max.z, .w = 1};
    
    // min_v4 = vector3MatrixProduct(BB.min, transform);
}

pub fn vector3MatrixProduct(v: rl.Vector3, M: rl.Matrix) rl.Vector3 {
    return rl.Vector3{  .x = M.m0*v.x + M.m4*v.y + M.m8*v.z + M.m12,
                        .y = M.m1*v.x + M.m5*v.y + M.m9*v.z + M.m13,
                        .z = M.m2*v.x + M.m6*v.y + M.m10*v.z + M.m14};
                        // .w = M.m3*v.x + M.m7*v.y + M.m11*v.z + M.m15};
}

pub fn createRect(v1: rl.Vector2, v2: rl.Vector2) rl.Rectangle {
    
    var x_min: f32 = undefined;
    var y_min: f32 = undefined;
    var height: f32 = undefined;
    var width: f32 = undefined;
    
    
    switch(v1.x < v2.x)
    {
        true => 
        {
            x_min = v1.x;
            width = v2.x - v1.x;
        },
        false =>
        {
            x_min = v2.x;
            width = v1.x - v2.x;
        },
    }
    
    switch(v1.y < v2.y)
    {
        true => 
        {
            y_min = v1.y;
            height = v2.y - v1.y;
        },
        false =>
        {
            y_min = v2.y;
            height = v1.y - v2.y;
        },
    }

    return rl.Rectangle{.x = x_min, .y = y_min, .width = width, .height = height};
}

pub fn withinRect(point: rl.Vector2, rec: rl.Rectangle) bool {
    if (point.x > rec.x and point.y > rec.y) {
        if(point.x < rec.x + rec.width and point.y < rec.y + rec.height){
            return true;
        }
    }
    return false;
}

pub fn Vector3Min(v1: rl.Vector3, v2: rl.Vector3) rl.Vector3{
    return .{   .x = if(v1.x <= v2.x) v1.x else v2.x,
                .y = if(v1.y <= v2.y) v1.y else v2.y,
                .z = if(v1.z <= v2.z) v1.z else v2.z};
}

pub fn Vector3Max(v1: rl.Vector3, v2: rl.Vector3) rl.Vector3{
    return .{   .x = if(v1.x >= v2.x) v1.x else v2.x,
                .y = if(v1.y >= v2.y) v1.y else v2.y,
                .z = if(v1.z >= v2.z) v1.z else v2.z};
}

pub fn vector3Inverse(v1: rl.Vector3) rl.Vector3{
    return rl.Vector3{.x = -v1.x, .y = -v1.y, .z = -v1.z};
}

pub fn matrixInvers(m: [16]f32) [16]f32 {
    // Use LU decomposition to find inverse
    // ASSUMES: diagonal is populated

    var L:[16]f32 = .{      1, 0, 0, 0,
                            0, 1, 0, 0,
                            0, 0, 1, 0,
                            0, 0, 0, 1};
    var U:[16]f32 = m;

    // Reduce upper to upper triangular form
    var i:u4 = 0;
    while(i<3):(i+=1){
        var j:u4 = 0;
        while(j<3-i):(j+=1){
            const multiplier = U[i*5+4*j]/U[i*5];
            if (multiplier == 0) continue;
            matrixRowAddition(&U, i+j+1, i, -multiplier);
            matrixRowAddition(&L, i+j+1, i, multiplier);
        }
    }

    // Make L and U inverse of themselves such that m = LU -> m^-1 = U^-1 * L^-1
    // inverse L (inplace cuz faster?)
    L[4] *= -1;
    L[8] *= -1;
    L[9] *= -1;
    L[12] *= -1;
    L[13] *= -1;
    L[14] *= -1;

    // inverse U
    var Uinverse:[16]f32 = .{   1, 0, 0, 0,
                                0, 1, 0, 0,
                                0, 0, 1, 0,
                                0, 0, 0, 1};

    i = 3;
    while(i>=0):(i-=1){ // 3,2,1,0
        const multiplier = 1/U[i*5];

        matrixRowMul(Uinverse, i, multiplier);
        
        var j:u4 = i-1;
        while(j>=0):(j-=1){ // e.g. i = 3 -> j = 2,1,0
            matrixRowAddition(&Uinverse, j, i, U[i*5-4*(i-j)]); // Index below entree in diagonal on row i, from bottom to top
        }
    }

    // Compute inverse of m using m = LU -> m^-1 = U^-1 * L^-1

    return matrixMul(Uinverse, L);
}

fn matrixRowAddition(m: *[16]f32, destRow: u4, sourceRow: u4, multiplier: f32) void {
    // Multiplies 'sourceRow' of matrix 'm' with 'multiplier', adds product to destRow

    const destInd   = destRow*4;
    const sourceInd = sourceRow*4;

    m[destInd] += m[sourceInd]*multiplier;
    m[destInd+1] += m[sourceInd+1]*multiplier;
    m[destInd+2] += m[sourceInd+2]*multiplier;
    m[destInd+3] += m[sourceInd+3]*multiplier;
}

fn matrixRowMul(m: *[16]f32, destRow: u4, multiplier: f32) void {
    // Multiplies 'sourceRow' of matrix 'm' with 'multiplier', adds product to destRow

    const destInd   = destRow*4;

    m[destInd] *= multiplier;
    m[destInd+1] *= multiplier;
    m[destInd+2] *= multiplier;
    m[destInd+3] *= multiplier;
}

fn matrixMul(A:[16]f32, B:[16]f32) [16]f32 {
    // const result: [16]f32 = undefined;
    
    const v1 = matrixVecMul(A, .{B[0], B[4], B[8],  B[12]});
    const v2 = matrixVecMul(A, .{B[1], B[5], B[9],  B[13]});
    const v3 = matrixVecMul(A, .{B[2], B[6], B[10], B[14]});
    const v4 = matrixVecMul(A, .{B[3], B[7], B[11], B[15]});
    
    return .{   v1[0], v2[0], v3[0], v4[0],
                v1[1], v2[1], v3[1], v4[1],
                v1[2], v2[2], v3[2], v4[2],
                v1[3], v2[3], v3[3], v4[3]};
}

fn matrixVecMul(A: [16]f32, b:[4]f32) [4]f32 {
    return .{   b[0] * A[0]  + b[1] * A[1]  + b[2] * A[2]  + b[3] * A[3],
                b[0] * A[4]  + b[1] * A[5]  + b[2] * A[6]  + b[3] * A[7],
                b[0] * A[8]  + b[1] * A[9]  + b[2] * A[10] + b[3] * A[11],
                b[0] * A[12] + b[1] * A[13] + b[2] * A[14] + b[3] * A[15]};
}

fn getRotMatrix(m: [16]f32) [9]f32 {
    return .{   m[0], m[1], m[2],
                m[4], m[5], m[6],
                m[8], m[9], m[10]};
}