const std = @import("std");
const ztg = @import("zentig");
const zrl = @import("zrl");
const rl = zrl.rl;
const c = @import("init.zig");
const Block = @import("block.zig");

const MeshData = @This();

alloc: std.mem.Allocator,

vao_id: c_uint = 0,
vbo_ids: [3]c_uint = .{0} ** 3,
buffer: []u32 = &.{},

vertices: std.ArrayListUnmanaged(Block.Index) = .{},
normals: std.ArrayListUnmanaged(Block.Side) = .{},
indices: std.ArrayListUnmanaged(c_ushort) = .{},
texcoords: std.ArrayListUnmanaged(f32) = .{},

// index key is vertex pos divided by 8, so vertex at (32, 48, 16) is keyed into (4, 6, 2)
vertex_to_index: std.AutoArrayHashMapUnmanaged(@Vector(3, u8), c_ushort) = .{},

pub fn deinit(self: *MeshData) void {
    self.vertices.deinit(self.alloc);
    self.texcoords.deinit(self.alloc);
    self.normals.deinit(self.alloc);
    self.indices.deinit(self.alloc);
}

pub fn registerVertex(self: *MeshData, v: Block.Index, side: Block.Side) !c_ushort {
    const key = v.toVector();

    //if (self.vertex_to_index.get(key)) |idx| return idx;

    const index: c_ushort = @intCast(self.vertices.items.len);
    try self.vertex_to_index.put(self.alloc, key, index);
    try self.vertices.append(self.alloc, v);
    try self.normals.append(self.alloc, side);

    return index;
}

pub fn generate(
    mesh_data: *MeshData,
    models: *c.Chunk.BlockModels,
    blocks: *c.Chunk.BlockArray,
    level_of_detail: u8,
) !void {
    if (level_of_detail == 1) {
        for (blocks.items, 0..) |block, i| {
            if (block.type == .none) continue;

            const block_index = Block.Index.fromArrayIndex(i);

            switch (block.type.get(.model_type)) {
                .block => {
                    for (std.enums.values(Block.Side)) |side| {
                        if (block.exposed.isSet(side.int()))
                            try mesh_data.addPlane(block_index, block.rotation, side, block.type, 1);
                    }
                },
                .model => |mesh_path| {
                    if (block.exposed.mask != 0) {
                        try models.append(mesh_data.alloc, .{ block_index, try Block.loadModel(mesh_data.alloc, mesh_path) });
                    }
                },
            }
        }
    } else {
        var block_x: u8 = 0;
        var block_y: u8 = 0;
        var block_z: u8 = 0;
        var inner_x: u8 = 0;
        var inner_y: u8 = 0;
        var inner_z: u8 = 0;
        var count: usize = 0;
        var average_color: @Vector(3, f32) = @splat(0);
        while (block_x < c.Chunk.BlockArray.x_len) : ({
            block_x += level_of_detail;
            block_y = 0;
        }) while (block_y < c.Chunk.BlockArray.y_len) : ({
            block_y += level_of_detail;
            block_z = 0;
        }) outer: while (block_z < c.Chunk.BlockArray.z_len) : ({
            block_z += level_of_detail;
            inner_x = 0;
            count = 0;
            average_color = @splat(0);
        }) while (inner_x < level_of_detail) : ({
            inner_x += 1;
            inner_y = 0;
        }) while (inner_y < level_of_detail) : ({
            inner_y += 1;
            inner_z = 0;
        }) while (inner_z < level_of_detail) : (inner_z += 1) {
            const block = blocks.get(block_x + inner_x, block_y + inner_y, block_z + inner_z);
            if (block.exposed.mask != 0 and block.type != .none) {
                const block_avg_color = Block.block_info.get(block.type).average_color;
                average_color += block_avg_color;
                count += 1;
            }

            if (count < (level_of_detail * 3) / 4) {
                continue;
            }

            const block_pos = Block.Index.init(block_x, block_y, block_z);
            const prior_vertex_count = mesh_data.vertices.items.len;

            for (std.enums.values(Block.Side)) |side|
                try mesh_data.addPlane(block_pos, .{}, side, .none, level_of_detail);

            const count_vec: @Vector(3, f32) = @splat(@floatFromInt(count));
            const average_color_u8: @Vector(3, u8) = @intFromFloat(average_color / count_vec);

            const colors_needed = mesh_data.vertices.items.len - prior_vertex_count;
            for (0..colors_needed) |i| {
                const rgb: packed struct(u32) {
                    r: u8,
                    g: u8,
                    b: u8,
                    _0: u8 = 0,
                } = .{
                    .r = average_color_u8[0],
                    .g = average_color_u8[1],
                    .b = average_color_u8[2],
                };

                mesh_data.texcoords.items[mesh_data.texcoords.items.len - (i * 2) - 1] = @bitCast(rgb);
            }

            continue :outer;
        };
    }
}

pub fn upload(mesh: *MeshData, dynamic: bool) !void {
    if (mesh.vao_id > 0) {
        // Check if mesh has already been loaded in GPU
        std.log.warn("VAO: [ID {}] Trying to re-load an already loaded mesh", .{mesh.vao_id});
        return;
    }

    mesh.vao_id = 0; // Vertex Array Object
    @memset(&mesh.vbo_ids, 0);

    mesh.vao_id = rl.rlLoadVertexArray();
    _ = rl.rlEnableVertexArray(mesh.vao_id);
    defer rl.rlDisableVertexArray();

    // NOTE: Vertex attributes must be uploaded considering
    // default locations points and available vertex data

    mesh.buffer = try mesh.alloc.alloc(u32, mesh.vertices.items.len);
    errdefer mesh.alloc.free(mesh.buffer);

    const VertexData = packed struct(u32) {
        x: u8,
        y: u8,
        z: u8,
        normal: u8,
    };

    for (
        mesh.buffer,
        mesh.vertices.items,
        mesh.normals.items,
    ) |*o, vertex, normal| {
        o.* = @bitCast(VertexData{
            .x = vertex.x,
            .y = vertex.y,
            .z = vertex.z,
            .normal = @intFromEnum(normal),
        });
    }

    // Enable vertex attributes: position (shader-location = 0)
    mesh.vbo_ids[0] = rl.rlLoadVertexBuffer(
        mesh.buffer.ptr,
        @intCast(mesh.buffer.len * @sizeOf(u32)),
        dynamic,
    );
    rl.rlSetVertexAttributeI(0, 1, rl.RL_UNSIGNED_INT, 0, null);
    rl.rlEnableVertexAttribute(0);

    // Enable vertex attributes: texcoords (shader-location = 1)
    mesh.vbo_ids[1] = rl.rlLoadVertexBuffer(
        mesh.texcoords.items.ptr,
        @intCast(mesh.texcoords.items.len * @sizeOf(f32)),
        dynamic,
    );
    rl.rlSetVertexAttribute(1, 2, rl.RL_FLOAT, false, 0, null);
    rl.rlEnableVertexAttribute(1);

    //if (buffer.len * 2 != mesh.texcoords.items.len) {
    //    std.log.info("vertices: {} != texcoords: {}", .{ buffer.len, mesh.texcoords.items.len });
    //}
    //std.debug.assert(buffer.len * 2 == mesh.texcoords.items.len);

    mesh.vbo_ids[2] = rl.rlLoadVertexBufferElement(
        mesh.indices.items.ptr,
        @intCast(mesh.indices.items.len * @sizeOf(c_ushort)),
        dynamic,
    );

    if (mesh.vao_id > 0) {
        //std.log.info("VAO: [ID {}] Mesh uploaded successfully to VRAM (GPU)", .{mesh.vao_id});
    } else {
        // wait so even if vao_id is 0 we say successful???
        std.log.warn("Raylib would say we did it successfully, but idk its weird...", .{});
    }
}

pub fn unload(mesh: *MeshData) void {
    // Unload rlgl mesh vboId data
    rl.rlUnloadVertexArray(mesh.vao_id);

    for (mesh.vbo_ids) |id|
        rl.rlUnloadVertexBuffer(id);

    mesh.normals.deinit(mesh.alloc);
    mesh.texcoords.deinit(mesh.alloc);
    mesh.vertices.deinit(mesh.alloc);
    mesh.indices.deinit(mesh.alloc);
    mesh.vertex_to_index.deinit(mesh.alloc);
    mesh.alloc.free(mesh.buffer);
}

pub fn addPlane(mesh_data: *MeshData, origin: Block.Index, rotation: Block.Rotation, side: Block.Side, block_type: Block.Type, scale: u8) !void {
    const vertices: [4]@Vector(3, u8) = switch (side) {
        //   2---3 z
        //   |   | |
        //  (0)--1 y--x
        .top => .{
            .{ 0, scale, 0 },
            .{ scale, scale, 0 },
            .{ 0, scale, scale },
            .{ scale, scale, scale },
        },
        .bottom => .{
            .{ 0, 0, scale },
            .{ scale, 0, scale },
            .{ 0, 0, 0 },
            .{ scale, 0, 0 },
        },
        .west => .{
            .{ 0, scale, scale },
            .{ 0, 0, scale },
            .{ 0, scale, 0 },
            .{ 0, 0, 0 },
        },
        .east => .{
            .{ scale, scale, scale },
            .{ scale, scale, 0 },
            .{ scale, 0, scale },
            .{ scale, 0, 0 },
        },
        .north => .{
            .{ 0, 0, scale },
            .{ 0, scale, scale },
            .{ scale, 0, scale },
            .{ scale, scale, scale },
        },
        .south => .{
            .{ scale, scale, 0 },
            .{ 0, scale, 0 },
            .{ scale, 0, 0 },
            .{ 0, 0, 0 },
        },
    };

    var indices: [4]c_ushort = undefined;
    for (vertices, &indices) |vertex, *index| {
        index.* = try mesh_data.registerVertex(origin.addVector(vertex), side);
    }
    try mesh_data.indices.appendSlice(mesh_data.alloc, &.{
        indices[2],
        indices[1],
        indices[0],
        indices[2],
        indices[3],
        indices[1],
    });

    const tex_coords: [8]f32 = if (block_type == .none) .{
        -1, 0,
        -1, 0,
        -1, 0,
        -1, 0,
    } else Block.texCoordsForSide(block_type, rotation, side);

    try mesh_data.texcoords.appendSlice(mesh_data.alloc, &tex_coords);
}

pub fn draw(mesh: MeshData, material: rl.Material, transform: rl.Matrix) void {
    // Bind shader program
    rl.rlEnableShader(material.shader.id);
    // Disable shader program
    defer rl.rlDisableShader();

    // Send required data to shader (matrices, values)
    //-----------------------------------------------------
    // Upload to shader material.colDiffuse
    if (material.shader.locs[rl.SHADER_LOC_COLOR_DIFFUSE] != -1) {
        const values: [4]f32 = .{
            @as(f32, @floatFromInt(material.maps[rl.MATERIAL_MAP_DIFFUSE].color.r)) / 255.0,
            @as(f32, @floatFromInt(material.maps[rl.MATERIAL_MAP_DIFFUSE].color.g)) / 255.0,
            @as(f32, @floatFromInt(material.maps[rl.MATERIAL_MAP_DIFFUSE].color.b)) / 255.0,
            @as(f32, @floatFromInt(material.maps[rl.MATERIAL_MAP_DIFFUSE].color.a)) / 255.0,
        };

        rl.rlSetUniform(material.shader.locs[rl.SHADER_LOC_COLOR_DIFFUSE], &values, rl.SHADER_UNIFORM_VEC4, 1);
    }

    // Upload to shader material.colSpecular (if location available)
    //if (material.shader.locs[rl.SHADER_LOC_COLOR_SPECULAR] != -1) {
    //    const values: [4]f32 = .{
    //        @as(f32, @floatFromInt(material.maps[rl.MATERIAL_MAP_SPECULAR].color.r)) / 255.0,
    //        @as(f32, @floatFromInt(material.maps[rl.MATERIAL_MAP_SPECULAR].color.g)) / 255.0,
    //        @as(f32, @floatFromInt(material.maps[rl.MATERIAL_MAP_SPECULAR].color.b)) / 255.0,
    //        @as(f32, @floatFromInt(material.maps[rl.MATERIAL_MAP_SPECULAR].color.a)) / 255.0,
    //    };

    //    rl.rlSetUniform(material.shader.locs[rl.SHADER_LOC_COLOR_SPECULAR], &values, rl.SHADER_UNIFORM_VEC4, 1);
    //}

    // Get a copy of current matrices to work with,
    // just in case stereo render is required, and we need to modify them
    // NOTE: At this point the modelview matrix just contains the view matrix (camera)
    // That's because BeginMode3D() sets it and there is no model-drawing function
    // that modifies it, all use rlPushMatrix() and rlPopMatrix()
    var matModel = rl.MatrixIdentity();
    const matView = rl.rlGetMatrixModelview();
    var matModelView = rl.MatrixIdentity();
    const matProjection = rl.rlGetMatrixProjection();

    // Upload view and projection matrices (if locations available)
    if (material.shader.locs[rl.SHADER_LOC_MATRIX_VIEW] != -1)
        rl.rlSetUniformMatrix(
            material.shader.locs[rl.SHADER_LOC_MATRIX_VIEW],
            matView,
        );
    if (material.shader.locs[rl.SHADER_LOC_MATRIX_PROJECTION] != -1)
        rl.rlSetUniformMatrix(
            material.shader.locs[rl.SHADER_LOC_MATRIX_PROJECTION],
            matProjection,
        );

    // Model transformation matrix is sent to shader uniform location: SHADER_LOC_MATRIX_MODEL
    if (material.shader.locs[rl.SHADER_LOC_MATRIX_MODEL] != -1)
        rl.rlSetUniformMatrix(
            material.shader.locs[rl.SHADER_LOC_MATRIX_MODEL],
            transform,
        );

    // Accumulate several model transformations:
    //    transform: model transformation provided (includes DrawModel() params combined with model.transform)
    //    rlGetMatrixTransform(): rlgl internal transform matrix due to push/pop matrix stack
    matModel = rl.MatrixMultiply(transform, rl.rlGetMatrixTransform());

    // Get model-view matrix
    matModelView = rl.MatrixMultiply(matModel, matView);

    // Upload model normal matrix (if locations available)
    if (material.shader.locs[rl.SHADER_LOC_MATRIX_NORMAL] != -1)
        rl.rlSetUniformMatrix(
            material.shader.locs[rl.SHADER_LOC_MATRIX_NORMAL],
            rl.MatrixTranspose(rl.MatrixInvert(matModel)),
        );
    //-----------------------------------------------------

    // Bind active texture maps (if available)
    const max_material_maps = 12;
    for (0..max_material_maps) |i| {
        if (material.maps[i].texture.id > 0) {
            // Select current shader texture slot
            rl.rlActiveTextureSlot(@intCast(i));

            // Enable texture for active slot
            if ((i == rl.MATERIAL_MAP_IRRADIANCE) or
                (i == rl.MATERIAL_MAP_PREFILTER) or
                (i == rl.MATERIAL_MAP_CUBEMAP))
            {
                rl.rlEnableTextureCubemap(material.maps[i].texture.id);
            } else {
                rl.rlEnableTexture(material.maps[i].texture.id);
            }

            rl.rlSetUniform(material.shader.locs[rl.SHADER_LOC_MAP_DIFFUSE + i], &i, rl.SHADER_UNIFORM_INT, 1);
        }
    }
    // Unbind all bound texture maps
    defer for (0..max_material_maps) |i| {
        if (material.maps[i].texture.id > 0) {
            // Select current shader texture slot
            rl.rlActiveTextureSlot(@intCast(i));

            // Disable texture for active slot
            if ((i == rl.MATERIAL_MAP_IRRADIANCE) or
                (i == rl.MATERIAL_MAP_PREFILTER) or
                (i == rl.MATERIAL_MAP_CUBEMAP))
            {
                rl.rlDisableTextureCubemap();
            } else {
                rl.rlDisableTexture();
            }
        }
    };

    // BIND MESH VBO STUFF
    if (!rl.rlEnableVertexArray(mesh.vao_id)) {
        // Bind mesh VBO data: vertex position (shader-location = 0)
        rl.rlEnableVertexBuffer(mesh.vbo_ids[0]);
        rl.rlSetVertexAttributeI(0, 1, rl.RL_UNSIGNED_INT, 0, null);
        rl.rlEnableVertexAttribute(0);

        // Bind mesh VBO data: vertex texcoords (shader-location = 1)
        rl.rlEnableVertexBuffer(mesh.vbo_ids[1]);
        rl.rlSetVertexAttribute(1, 2, rl.RL_FLOAT, false, 0, null);
        rl.rlEnableVertexAttribute(1);

        rl.rlEnableVertexBufferElement(mesh.vbo_ids[2]);
    }

    const eye_count: u8 = if (rl.rlIsStereoRenderEnabled()) 2 else 1;

    for (0..eye_count) |eye| {
        // Calculate model-view-projection matrix (MVP)
        const mat_model_view_projection = if (eye_count == 1) blk: {
            break :blk rl.MatrixMultiply(matModelView, matProjection);
        } else blk: {
            // Setup current eye viewport (half screen width)
            rl.rlViewport(
                @divFloor(@as(i32, @intCast(eye)) * rl.rlGetFramebufferWidth(), 2),
                0,
                @divFloor(rl.rlGetFramebufferWidth(), 2),
                rl.rlGetFramebufferHeight(),
            );
            break :blk rl.MatrixMultiply(
                rl.MatrixMultiply(matModelView, rl.rlGetMatrixViewOffsetStereo(@intCast(eye))),
                rl.rlGetMatrixProjectionStereo(@intCast(eye)),
            );
        };

        // Send combined model-view-projection matrix to shader
        rl.rlSetUniformMatrix(material.shader.locs[rl.SHADER_LOC_MATRIX_MVP], mat_model_view_projection);

        // Draw mesh
        rl.rlDrawVertexArrayElements(0, @intCast(mesh.indices.items.len), null);
    }

    // Disable all possible vertex array objects (or VBOs)
    rl.rlDisableVertexArray();
    rl.rlDisableVertexBuffer();
    rl.rlDisableVertexBufferElement();

    // Restore rlgl internal modelview and projection matrices
    rl.rlSetMatrixModelview(matView);
    rl.rlSetMatrixProjection(matProjection);
}

fn genMeshPlane(alloc: std.mem.Allocator, width: f32, length: f32, _res_x: u32, _res_z: u32, facing: rl.Vector3) !rl.Mesh {
    var mesh: rl.Mesh = .{};

    const res_x_f: f32 = @floatFromInt(_res_x);
    const res_z_f: f32 = @floatFromInt(_res_z);

    const res_x = _res_x + 1;
    const res_z = _res_x + 1;

    // Vertices definition
    const vertexCount = res_x * res_z; // vertices get reused for the faces

    const vertices = try alloc.alloc(rl.Vector3, vertexCount); // (Vector3 *)RL_MALLOC(vertexCount*sizeof(Vector3));
    defer alloc.free(vertices);

    for (0..res_z) |z| {
        // [-length/2, length/2]
        const z_f: f32 = @floatFromInt(z);

        const zPos = (z_f / res_z_f - 0.5) * length;
        for (0..res_x) |x| {
            // [-width/2, width/2]
            const x_f: f32 = @floatFromInt(x);

            const xPos = (x_f / res_x_f - 0.5) * width;
            vertices[x + z * res_x] = .{ .x = xPos, .y = 0.0, .z = zPos };
        }
    }

    // Normals definition
    const normals = try alloc.alloc(rl.Vector3, vertexCount); //(Vector3 *)RL_MALLOC(vertexCount*sizeof(Vector3));
    defer alloc.free(normals);

    for (0..vertexCount) |n| normals[n] = facing; // Vector3.up;

    // TexCoords definition
    const texcoords = try alloc.alloc(rl.Vector2, vertexCount); //(Vector2 *)RL_MALLOC(vertexCount*sizeof(Vector2));
    defer alloc.free(texcoords);

    for (0..res_z) |v| {
        const v_f: f32 = @floatFromInt(v);
        for (0..res_x) |u| {
            const u_f: f32 = @floatFromInt(u);
            texcoords[u + v * res_x] = .{ .x = u_f / res_x_f, .y = v_f / res_z_f };
        }
    }

    // Triangles definition (indices)
    const numFaces = (res_x - 1) * (res_z - 1);
    const triangles = try alloc.alloc(u16, numFaces * 6); // (int *)RL_MALLOC(numFaces*6*sizeof(int));
    defer alloc.free(triangles);

    var t: usize = 0;
    for (0..numFaces) |face| {
        // Retrieve lower left corner from face ind
        const i = face + face / (res_x - 1);

        triangles[t] = @intCast(i + res_x);
        t += 1;
        triangles[t] = @intCast(i + 1);
        t += 1;
        triangles[t] = @intCast(i);
        t += 1;

        triangles[t] = @intCast(i + res_x);
        t += 1;
        triangles[t] = @intCast(i + res_x + 1);
        t += 1;
        triangles[t] = @intCast(i + 1);
        t += 1;
    }

    mesh.vertexCount = @intCast(vertexCount);
    mesh.triangleCount = @intCast(numFaces * 2);
    mesh.vertices = (try std.heap.raw_c_allocator.alloc(f32, vertexCount * 3)).ptr; // (float *)RL_MALLOC(mesh.vertexCount*3*sizeof(float));
    mesh.texcoords = (try std.heap.raw_c_allocator.alloc(f32, vertexCount * 2)).ptr; //(float *)RL_MALLOC(mesh.vertexCount*2*sizeof(float));
    mesh.normals = (try std.heap.raw_c_allocator.alloc(f32, vertexCount * 3)).ptr; //(float *)RL_MALLOC(mesh.vertexCount*3*sizeof(float));
    mesh.indices = (try std.heap.raw_c_allocator.alloc(c_ushort, @intCast(mesh.triangleCount * 3))).ptr; //(unsigned short *)RL_MALLOC(mesh.triangleCount*3*sizeof(unsigned short));

    // Mesh vertices position array
    for (0..vertexCount) |i| {
        mesh.vertices[3 * i] = vertices[i].x;
        mesh.vertices[3 * i + 1] = vertices[i].y;
        mesh.vertices[3 * i + 2] = vertices[i].z;
    }

    // Mesh texcoords array
    for (0..vertexCount) |i| {
        mesh.texcoords[2 * i] = texcoords[i].x;
        mesh.texcoords[2 * i + 1] = texcoords[i].y;
    }

    // Mesh normals array
    for (0..vertexCount) |i| {
        mesh.normals[3 * i] = normals[i].x;
        mesh.normals[3 * i + 1] = normals[i].y;
        mesh.normals[3 * i + 2] = normals[i].z;
    }

    // Mesh indices array initialization
    for (0..@intCast(mesh.triangleCount * 3)) |i| mesh.indices[i] = @intCast(triangles[i]);

    return mesh;
}
