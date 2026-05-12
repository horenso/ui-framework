const std = @import("std");

const sdl = @import("sdl");
const shaders = @import("shaders");

const vecImport = @import("vec.zig");
const Vec2f = vecImport.Vec2f;
const Vec4f = vecImport.Vec4f;
const Vec2i = vecImport.Vec2i;

const Color = @import("Color.zig");
const FontAtlas = @import("FontManager.zig").FontAtlas;

const DEBUG_DISABLE_CLIPPING = true;

pub const ATLAS_SIZE: u32 = 1024;

pub const Texture = struct { sdlTexture: *sdl.SDL_GPUTexture };

const SolidVertex = extern struct {
    x: f32,
    y: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const TexturedVertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const DrawCmd = struct {
    kind: enum { solid_tri, solid_line, textured_tri },
    offset: u32,
    count: u32,
    texture: ?*sdl.SDL_GPUTexture = null,
};

device: *sdl.SDL_GPUDevice,
window: *sdl.SDL_Window,
allocator: std.mem.Allocator,

solidPipeline: *sdl.SDL_GPUGraphicsPipeline,
linePipeline: *sdl.SDL_GPUGraphicsPipeline,
texturedPipeline: *sdl.SDL_GPUGraphicsPipeline,
sampler: *sdl.SDL_GPUSampler,

solidVerts: std.ArrayList(SolidVertex),
texturedVerts: std.ArrayList(TexturedVertex),
drawCmds: std.ArrayList(DrawCmd),

solidGpuBuffer: ?*sdl.SDL_GPUBuffer = null,
solidGpuCapacity: u32 = 0,
texturedGpuBuffer: ?*sdl.SDL_GPUBuffer = null,
texturedGpuCapacity: u32 = 0,
vertTransferBuffer: ?*sdl.SDL_GPUTransferBuffer = null,
vertTransferCapacity: u32 = 0,

windowSize: Vec2f = .{ 800, 600 },
clearColor: Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
frameActive: bool = false,

pendingAtlasUploads: std.ArrayList(*FontAtlas),

offset: Vec2f = .{ 0, 0 },
_clip: Vec2f = .{ 0, 0 },

pub fn init(allocator: std.mem.Allocator, sdlWindow: *sdl.SDL_Window) !@This() {
    const device = sdl.SDL_CreateGPUDevice(
        sdl.SDL_GPU_SHADERFORMAT_SPIRV,
        true,
        null,
    ) orelse {
        std.log.err("SDL_CreateGPUDevice() Error: {s}", .{sdl.SDL_GetError()});
        return error.InitFailure;
    };
    errdefer sdl.SDL_DestroyGPUDevice(device);

    if (!sdl.SDL_ClaimWindowForGPUDevice(device, sdlWindow)) {
        std.log.err("SDL_ClaimWindowForGPUDevice() Error: {s}", .{sdl.SDL_GetError()});
        return error.InitFailure;
    }
    errdefer sdl.SDL_ReleaseWindowFromGPUDevice(device, sdlWindow);

    _ = sdl.SDL_SetGPUSwapchainParameters(
        device,
        sdlWindow,
        sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
        sdl.SDL_GPU_PRESENTMODE_VSYNC,
    );

    const solidVert = try createShader(device, shaders.solid_vert, sdl.SDL_GPU_SHADERSTAGE_VERTEX, 0);
    defer sdl.SDL_ReleaseGPUShader(device, solidVert);

    const solidFrag = try createShader(device, shaders.solid_frag, sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 0);
    defer sdl.SDL_ReleaseGPUShader(device, solidFrag);

    const texturedVert = try createShader(device, shaders.textured_vert, sdl.SDL_GPU_SHADERSTAGE_VERTEX, 0);
    defer sdl.SDL_ReleaseGPUShader(device, texturedVert);

    const texturedFrag = try createShader(device, shaders.textured_frag, sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 1);
    defer sdl.SDL_ReleaseGPUShader(device, texturedFrag);

    const swapchainFormat = sdl.SDL_GetGPUSwapchainTextureFormat(device, sdlWindow);

    const solidPipeline = try createSolidPipeline(
        device,
        solidVert,
        solidFrag,
        swapchainFormat,
        sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
    );
    errdefer sdl.SDL_ReleaseGPUGraphicsPipeline(device, solidPipeline);

    const linePipeline = try createSolidPipeline(
        device,
        solidVert,
        solidFrag,
        swapchainFormat,
        sdl.SDL_GPU_PRIMITIVETYPE_LINELIST,
    );
    errdefer sdl.SDL_ReleaseGPUGraphicsPipeline(device, linePipeline);

    const texturedPipeline = try createTexturedPipeline(device, texturedVert, texturedFrag, swapchainFormat);
    errdefer sdl.SDL_ReleaseGPUGraphicsPipeline(device, texturedPipeline);

    const sampler = sdl.SDL_CreateGPUSampler(device, &.{
        .min_filter = sdl.SDL_GPU_FILTER_LINEAR,
        .mag_filter = sdl.SDL_GPU_FILTER_LINEAR,
        .mipmap_mode = sdl.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    }) orelse {
        std.log.err("SDL_CreateGPUSampler() Error: {s}", .{sdl.SDL_GetError()});
        return error.InitFailure;
    };

    return .{
        .device = device,
        .window = sdlWindow,
        .allocator = allocator,
        .solidPipeline = solidPipeline,
        .linePipeline = linePipeline,
        .texturedPipeline = texturedPipeline,
        .sampler = sampler,
        .solidVerts = .empty,
        .texturedVerts = .empty,
        .drawCmds = .empty,
        .pendingAtlasUploads = .empty,
    };
}

fn createShader(
    device: *sdl.SDL_GPUDevice,
    code: []const u8,
    stage: sdl.SDL_GPUShaderStage,
    numSamplers: u32,
) !*sdl.SDL_GPUShader {
    const info: sdl.SDL_GPUShaderCreateInfo = .{
        .code = code.ptr,
        .code_size = code.len,
        .entrypoint = "main",
        .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = stage,
        .num_samplers = numSamplers,
        .num_uniform_buffers = 0,
        .num_storage_buffers = 0,
        .num_storage_textures = 0,
    };
    return sdl.SDL_CreateGPUShader(device, &info) orelse {
        std.log.err("SDL_CreateGPUShader() Error: {s}", .{sdl.SDL_GetError()});
        return error.InitFailure;
    };
}

fn blendState() sdl.SDL_GPUColorTargetBlendState {
    return .{
        .enable_blend = true,
        .color_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
        .alpha_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
        .src_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
        .dst_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .src_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE,
        .dst_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
    };
}

fn createSolidPipeline(
    device: *sdl.SDL_GPUDevice,
    vert: *sdl.SDL_GPUShader,
    frag: *sdl.SDL_GPUShader,
    swapchainFormat: sdl.SDL_GPUTextureFormat,
    primitive: sdl.SDL_GPUPrimitiveType,
) !*sdl.SDL_GPUGraphicsPipeline {
    var colorTargets = [_]sdl.SDL_GPUColorTargetDescription{.{
        .format = swapchainFormat,
        .blend_state = blendState(),
    }};
    var vertexBuffers = [_]sdl.SDL_GPUVertexBufferDescription{.{
        .slot = 0,
        .pitch = @sizeOf(SolidVertex),
        .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
        .instance_step_rate = 0,
    }};
    var vertexAttrs = [_]sdl.SDL_GPUVertexAttribute{
        .{ .buffer_slot = 0, .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .location = 0, .offset = 0 },
        .{ .buffer_slot = 0, .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .location = 1, .offset = @sizeOf(f32) * 2 },
    };

    const info: sdl.SDL_GPUGraphicsPipelineCreateInfo = .{
        .vertex_shader = vert,
        .fragment_shader = frag,
        .primitive_type = primitive,
        .rasterizer_state = .{
            .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
            .cull_mode = sdl.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl.SDL_GPU_FRONTFACE_CLOCKWISE,
        },
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &vertexBuffers,
            .num_vertex_buffers = vertexBuffers.len,
            .vertex_attributes = &vertexAttrs,
            .num_vertex_attributes = vertexAttrs.len,
        },
        .target_info = .{
            .color_target_descriptions = &colorTargets,
            .num_color_targets = colorTargets.len,
        },
    };
    return sdl.SDL_CreateGPUGraphicsPipeline(device, &info) orelse {
        std.log.err("SDL_CreateGPUGraphicsPipeline() Error: {s}", .{sdl.SDL_GetError()});
        return error.InitFailure;
    };
}

fn createTexturedPipeline(
    device: *sdl.SDL_GPUDevice,
    vert: *sdl.SDL_GPUShader,
    frag: *sdl.SDL_GPUShader,
    swapchainFormat: sdl.SDL_GPUTextureFormat,
) !*sdl.SDL_GPUGraphicsPipeline {
    var colorTargets = [_]sdl.SDL_GPUColorTargetDescription{.{
        .format = swapchainFormat,
        .blend_state = blendState(),
    }};
    var vertexBuffers = [_]sdl.SDL_GPUVertexBufferDescription{.{
        .slot = 0,
        .pitch = @sizeOf(TexturedVertex),
        .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
        .instance_step_rate = 0,
    }};
    var vertexAttrs = [_]sdl.SDL_GPUVertexAttribute{
        .{ .buffer_slot = 0, .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .location = 0, .offset = 0 },
        .{ .buffer_slot = 0, .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .location = 1, .offset = @sizeOf(f32) * 2 },
        .{ .buffer_slot = 0, .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .location = 2, .offset = @sizeOf(f32) * 4 },
    };

    const info: sdl.SDL_GPUGraphicsPipelineCreateInfo = .{
        .vertex_shader = vert,
        .fragment_shader = frag,
        .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
            .cull_mode = sdl.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl.SDL_GPU_FRONTFACE_CLOCKWISE,
        },
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &vertexBuffers,
            .num_vertex_buffers = vertexBuffers.len,
            .vertex_attributes = &vertexAttrs,
            .num_vertex_attributes = vertexAttrs.len,
        },
        .target_info = .{
            .color_target_descriptions = &colorTargets,
            .num_color_targets = colorTargets.len,
        },
    };
    return sdl.SDL_CreateGPUGraphicsPipeline(device, &info) orelse {
        std.log.err("SDL_CreateGPUGraphicsPipeline() Error: {s}", .{sdl.SDL_GetError()});
        return error.InitFailure;
    };
}

pub fn deinit(self: *@This()) void {
    if (self.solidGpuBuffer) |buf| sdl.SDL_ReleaseGPUBuffer(self.device, buf);
    if (self.texturedGpuBuffer) |buf| sdl.SDL_ReleaseGPUBuffer(self.device, buf);
    if (self.vertTransferBuffer) |buf| sdl.SDL_ReleaseGPUTransferBuffer(self.device, buf);

    sdl.SDL_ReleaseGPUSampler(self.device, self.sampler);
    sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, self.texturedPipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, self.linePipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, self.solidPipeline);

    self.solidVerts.deinit(self.allocator);
    self.texturedVerts.deinit(self.allocator);
    self.drawCmds.deinit(self.allocator);
    self.pendingAtlasUploads.deinit(self.allocator);

    sdl.SDL_ReleaseWindowFromGPUDevice(self.device, self.window);
    sdl.SDL_DestroyGPUDevice(self.device);
}

pub fn setClip(self: *@This(), clip: Vec2f) void {
    if (DEBUG_DISABLE_CLIPPING) {
        return;
    }
    self._clip = clip;
    // TODO: SDL_SetGPUScissor inside render pass — currently we defer drawing
    // to present(), so scissor would need to be recorded per draw command.
}

fn cpos(self: *const @This(), x: f32, y: f32) struct { f32, f32 } {
    const sx = (x + self.offset[0]) / self.windowSize[0] * 2.0 - 1.0;
    const sy = 1.0 - (y + self.offset[1]) / self.windowSize[1] * 2.0;
    return .{ sx, sy };
}

fn fcolor(c: Color) struct { f32, f32, f32, f32 } {
    return .{
        @as(f32, @floatFromInt(c.r)) / 255.0,
        @as(f32, @floatFromInt(c.g)) / 255.0,
        @as(f32, @floatFromInt(c.b)) / 255.0,
        @as(f32, @floatFromInt(c.a)) / 255.0,
    };
}

fn pushSolidVerts(self: *@This(), verts: []const SolidVertex, kind: enum { tri, line }) void {
    const offset: u32 = @intCast(self.solidVerts.items.len);
    self.solidVerts.appendSlice(self.allocator, verts) catch @panic("OOM");

    const cmdKind: @FieldType(DrawCmd, "kind") = switch (kind) {
        .tri => .solid_tri,
        .line => .solid_line,
    };

    if (self.drawCmds.items.len > 0) {
        const last = &self.drawCmds.items[self.drawCmds.items.len - 1];
        if (last.kind == cmdKind) {
            last.count += @intCast(verts.len);
            return;
        }
    }
    self.drawCmds.append(self.allocator, .{
        .kind = cmdKind,
        .offset = offset,
        .count = @intCast(verts.len),
    }) catch @panic("OOM");
}

fn pushTexturedVerts(self: *@This(), verts: []const TexturedVertex, texture: *sdl.SDL_GPUTexture) void {
    const offset: u32 = @intCast(self.texturedVerts.items.len);
    self.texturedVerts.appendSlice(self.allocator, verts) catch @panic("OOM");

    if (self.drawCmds.items.len > 0) {
        const last = &self.drawCmds.items[self.drawCmds.items.len - 1];
        if (last.kind == .textured_tri and last.texture == texture) {
            last.count += @intCast(verts.len);
            return;
        }
    }
    self.drawCmds.append(self.allocator, .{
        .kind = .textured_tri,
        .offset = offset,
        .count = @intCast(verts.len),
        .texture = texture,
    }) catch @panic("OOM");
}

pub fn clear(self: *@This(), color: Color) void {
    self.clearColor = color;
    self.solidVerts.clearRetainingCapacity();
    self.texturedVerts.clearRetainingCapacity();
    self.drawCmds.clearRetainingCapacity();
    self.pendingAtlasUploads.clearRetainingCapacity();

    var w: c_int = 0;
    var h: c_int = 0;
    _ = sdl.SDL_GetWindowSizeInPixels(self.window, &w, &h);
    self.windowSize = .{ @floatFromInt(@max(w, 1)), @floatFromInt(@max(h, 1)) };

    self.frameActive = true;
}

pub fn outline(self: *@This(), rect: Vec4f, color: Color) void {
    const x0 = rect[0];
    const y0 = rect[1];
    const x1 = rect[0] + rect[2];
    const y1 = rect[1] + rect[3];
    const c = fcolor(color);

    var verts: [8]SolidVertex = undefined;
    inline for (.{
        .{ x0, y0, x1, y0 },
        .{ x1, y0, x1, y1 },
        .{ x1, y1, x0, y1 },
        .{ x0, y1, x0, y0 },
    }, 0..) |seg, i| {
        const a = self.cpos(seg[0], seg[1]);
        const b = self.cpos(seg[2], seg[3]);
        verts[i * 2] = .{ .x = a[0], .y = a[1], .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
        verts[i * 2 + 1] = .{ .x = b[0], .y = b[1], .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
    }
    self.pushSolidVerts(&verts, .line);
}

pub fn fillRect(self: *@This(), rect: Vec4f, color: Color) void {
    const x0 = rect[0];
    const y0 = rect[1];
    const x1 = rect[0] + rect[2];
    const y1 = rect[1] + rect[3];
    const c = fcolor(color);

    const tl = self.cpos(x0, y0);
    const tr = self.cpos(x1, y0);
    const bl = self.cpos(x0, y1);
    const br = self.cpos(x1, y1);

    const verts = [_]SolidVertex{
        .{ .x = tl[0], .y = tl[1], .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
        .{ .x = tr[0], .y = tr[1], .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
        .{ .x = br[0], .y = br[1], .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
        .{ .x = tl[0], .y = tl[1], .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
        .{ .x = br[0], .y = br[1], .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
        .{ .x = bl[0], .y = bl[1], .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
    };
    self.pushSolidVerts(&verts, .tri);
}

pub fn line(self: *@This(), p1: Vec2f, p2: Vec2f, color: Color) void {
    const c = fcolor(color);
    const a = self.cpos(p1[0], p1[1]);
    const b = self.cpos(p2[0], p2[1]);
    const verts = [_]SolidVertex{
        .{ .x = a[0], .y = a[1], .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
        .{ .x = b[0], .y = b[1], .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
    };
    self.pushSolidVerts(&verts, .line);
}

pub fn createTexture(self: @This()) Texture {
    const info: sdl.SDL_GPUTextureCreateInfo = .{
        .type = sdl.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl.SDL_GPU_TEXTUREFORMAT_R8_UNORM,
        .usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = ATLAS_SIZE,
        .height = ATLAS_SIZE,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
    };
    const tex = sdl.SDL_CreateGPUTexture(self.device, &info) orelse @panic("SDL_CreateGPUTexture failed");
    return .{ .sdlTexture = tex };
}

pub fn destroyTexture(self: @This(), texture: Texture) void {
    sdl.SDL_ReleaseGPUTexture(self.device, texture.sdlTexture);
}

pub fn drawCharacter(
    self: *@This(),
    allocator: std.mem.Allocator,
    codepoint: u32,
    fontAtlas: *FontAtlas,
    pos: Vec2f,
    color: Color,
) void {
    const glyph = fontAtlas.getGlyph(allocator, codepoint) catch @panic("unexpected");

    if (fontAtlas.dirty) {
        fontAtlas.dirty = false;
        // De-duplicate (same atlas could become dirty multiple times this frame)
        var alreadyQueued = false;
        for (self.pendingAtlasUploads.items) |a| {
            if (a == fontAtlas) {
                alreadyQueued = true;
                break;
            }
        }
        if (!alreadyQueued) {
            self.pendingAtlasUploads.append(self.allocator, fontAtlas) catch @panic("OOM");
        }
    }

    const sw: f32 = @floatFromInt(glyph.size[0]);
    const sh: f32 = @floatFromInt(glyph.size[1]);
    const x0 = @round(pos[0] + @as(f32, @floatFromInt(glyph.bearing[0])));
    const y0 = @round(pos[1] + fontAtlas.height - @as(f32, @floatFromInt(glyph.bearing[1])) + fontAtlas.baseline);
    const x1 = x0 + sw;
    const y1 = y0 + sh;

    const uL = glyph.uv[0];
    const vT = glyph.uv[1];
    const uR = glyph.uv[2];
    const vB = glyph.uv[3];

    const c = fcolor(color);

    const tl = self.cpos(x0, y0);
    const tr = self.cpos(x1, y0);
    const bl = self.cpos(x0, y1);
    const br = self.cpos(x1, y1);

    const verts = [_]TexturedVertex{
        .{ .x = tl[0], .y = tl[1], .u = uL, .v = vT, .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
        .{ .x = tr[0], .y = tr[1], .u = uR, .v = vT, .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
        .{ .x = br[0], .y = br[1], .u = uR, .v = vB, .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
        .{ .x = tl[0], .y = tl[1], .u = uL, .v = vT, .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
        .{ .x = br[0], .y = br[1], .u = uR, .v = vB, .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
        .{ .x = bl[0], .y = bl[1], .u = uL, .v = vB, .r = c[0], .g = c[1], .b = c[2], .a = c[3] },
    };
    self.pushTexturedVerts(&verts, fontAtlas.texture);
}

fn ensureGpuBuffer(
    self: *@This(),
    slot: *?*sdl.SDL_GPUBuffer,
    capSlot: *u32,
    required: u32,
) void {
    if (required == 0) return;
    if (slot.* != null and capSlot.* >= required) return;
    if (slot.*) |buf| sdl.SDL_ReleaseGPUBuffer(self.device, buf);
    const newCap: u32 = @max(required, capSlot.* * 2);
    const info: sdl.SDL_GPUBufferCreateInfo = .{
        .usage = sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
        .size = newCap,
    };
    slot.* = sdl.SDL_CreateGPUBuffer(self.device, &info) orelse @panic("SDL_CreateGPUBuffer failed");
    capSlot.* = newCap;
}

fn ensureTransferBuffer(self: *@This(), required: u32) void {
    if (required == 0) return;
    if (self.vertTransferBuffer != null and self.vertTransferCapacity >= required) return;
    if (self.vertTransferBuffer) |buf| sdl.SDL_ReleaseGPUTransferBuffer(self.device, buf);
    const newCap: u32 = @max(required, self.vertTransferCapacity * 2);
    const info: sdl.SDL_GPUTransferBufferCreateInfo = .{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = newCap,
    };
    self.vertTransferBuffer = sdl.SDL_CreateGPUTransferBuffer(self.device, &info) orelse @panic("SDL_CreateGPUTransferBuffer failed");
    self.vertTransferCapacity = newCap;
}

pub fn present(self: *@This()) void {
    if (!self.frameActive) return;
    self.frameActive = false;

    const solidBytes: u32 = @intCast(self.solidVerts.items.len * @sizeOf(SolidVertex));
    const texBytes: u32 = @intCast(self.texturedVerts.items.len * @sizeOf(TexturedVertex));
    const totalVertBytes: u32 = solidBytes + texBytes;

    self.ensureGpuBuffer(&self.solidGpuBuffer, &self.solidGpuCapacity, solidBytes);
    self.ensureGpuBuffer(&self.texturedGpuBuffer, &self.texturedGpuCapacity, texBytes);
    self.ensureTransferBuffer(totalVertBytes);

    const cmdBuf = sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
        std.log.err("SDL_AcquireGPUCommandBuffer: {s}", .{sdl.SDL_GetError()});
        return;
    };

    // Upload vertex data
    if (totalVertBytes > 0) {
        const mapped: [*]u8 = @ptrCast(sdl.SDL_MapGPUTransferBuffer(self.device, self.vertTransferBuffer.?, true) orelse @panic("MapGPUTransferBuffer failed"));
        if (solidBytes > 0) {
            @memcpy(mapped[0..solidBytes], std.mem.sliceAsBytes(self.solidVerts.items));
        }
        if (texBytes > 0) {
            @memcpy(mapped[solidBytes .. solidBytes + texBytes], std.mem.sliceAsBytes(self.texturedVerts.items));
        }
        sdl.SDL_UnmapGPUTransferBuffer(self.device, self.vertTransferBuffer.?);
    }

    const copyPass = sdl.SDL_BeginGPUCopyPass(cmdBuf);

    if (solidBytes > 0) {
        sdl.SDL_UploadToGPUBuffer(
            copyPass,
            &.{ .transfer_buffer = self.vertTransferBuffer.?, .offset = 0 },
            &.{ .buffer = self.solidGpuBuffer.?, .offset = 0, .size = solidBytes },
            true,
        );
    }
    if (texBytes > 0) {
        sdl.SDL_UploadToGPUBuffer(
            copyPass,
            &.{ .transfer_buffer = self.vertTransferBuffer.?, .offset = solidBytes },
            &.{ .buffer = self.texturedGpuBuffer.?, .offset = 0, .size = texBytes },
            true,
        );
    }

    for (self.pendingAtlasUploads.items) |atlas| {
        const mapped: [*]u8 = @ptrCast(sdl.SDL_MapGPUTransferBuffer(
            self.device,
            atlas.transferBuffer,
            true,
        ) orelse @panic("MapGPUTransferBuffer failed for atlas"));
        @memcpy(mapped[0 .. ATLAS_SIZE * ATLAS_SIZE], atlas.cpuPixels);
        sdl.SDL_UnmapGPUTransferBuffer(self.device, atlas.transferBuffer);

        sdl.SDL_UploadToGPUTexture(
            copyPass,
            &.{
                .transfer_buffer = atlas.transferBuffer,
                .offset = 0,
                .pixels_per_row = ATLAS_SIZE,
                .rows_per_layer = ATLAS_SIZE,
            },
            &.{
                .texture = atlas.texture,
                .mip_level = 0,
                .layer = 0,
                .x = 0,
                .y = 0,
                .z = 0,
                .w = ATLAS_SIZE,
                .h = ATLAS_SIZE,
                .d = 1,
            },
            true,
        );
    }

    sdl.SDL_EndGPUCopyPass(copyPass);

    // Acquire swapchain
    var swapchainTexture: ?*sdl.SDL_GPUTexture = null;
    if (!sdl.SDL_WaitAndAcquireGPUSwapchainTexture(cmdBuf, self.window, &swapchainTexture, null, null)) {
        std.log.warn("SDL_WaitAndAcquireGPUSwapchainTexture: {s}", .{sdl.SDL_GetError()});
        _ = sdl.SDL_SubmitGPUCommandBuffer(cmdBuf);
        return;
    }

    if (swapchainTexture == null) {
        // Window minimized; nothing to draw.
        _ = sdl.SDL_SubmitGPUCommandBuffer(cmdBuf);
        return;
    }

    const cc = fcolor(self.clearColor);
    const colorTarget: sdl.SDL_GPUColorTargetInfo = .{
        .texture = swapchainTexture,
        .clear_color = .{ .r = cc[0], .g = cc[1], .b = cc[2], .a = cc[3] },
        .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl.SDL_GPU_STOREOP_STORE,
        .cycle = false,
    };

    const renderPass = sdl.SDL_BeginGPURenderPass(cmdBuf, &colorTarget, 1, null) orelse {
        std.log.err("SDL_BeginGPURenderPass: {s}", .{sdl.SDL_GetError()});
        _ = sdl.SDL_SubmitGPUCommandBuffer(cmdBuf);
        return;
    };

    var lastKind: ?@FieldType(DrawCmd, "kind") = null;
    var lastTexture: ?*sdl.SDL_GPUTexture = null;

    for (self.drawCmds.items) |cmd| {
        const switchPipeline = lastKind == null or lastKind.? != cmd.kind;
        if (switchPipeline) {
            switch (cmd.kind) {
                .solid_tri => sdl.SDL_BindGPUGraphicsPipeline(renderPass, self.solidPipeline),
                .solid_line => sdl.SDL_BindGPUGraphicsPipeline(renderPass, self.linePipeline),
                .textured_tri => sdl.SDL_BindGPUGraphicsPipeline(renderPass, self.texturedPipeline),
            }
            switch (cmd.kind) {
                .solid_tri, .solid_line => {
                    sdl.SDL_BindGPUVertexBuffers(renderPass, 0, &.{
                        .buffer = self.solidGpuBuffer.?,
                        .offset = 0,
                    }, 1);
                },
                .textured_tri => {
                    sdl.SDL_BindGPUVertexBuffers(renderPass, 0, &.{
                        .buffer = self.texturedGpuBuffer.?,
                        .offset = 0,
                    }, 1);
                },
            }
            lastKind = cmd.kind;
            lastTexture = null;
        }

        if (cmd.kind == .textured_tri) {
            if (lastTexture != cmd.texture) {
                sdl.SDL_BindGPUFragmentSamplers(renderPass, 0, &.{
                    .texture = cmd.texture.?,
                    .sampler = self.sampler,
                }, 1);
                lastTexture = cmd.texture;
            }
        }

        sdl.SDL_DrawGPUPrimitives(renderPass, cmd.count, 1, cmd.offset, 0);
    }

    sdl.SDL_EndGPURenderPass(renderPass);
    _ = sdl.SDL_SubmitGPUCommandBuffer(cmdBuf);
}
