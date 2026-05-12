const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl_mod = createSdlModule(b, target, optimize);
    const freetype_mod = createFreetypeModule(b, target, optimize);
    const shaders_mod = createShadersModule(b);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("sdl", sdl_mod);
    exe_mod.addImport("freetype", freetype_mod);
    exe_mod.addImport("shaders", shaders_mod);

    const exe = b.addExecutable(.{
        .name = "ui_framework",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn createSdlModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c/sdl.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(sdl_dep.path("include"));

    const module = translate_c.createModule();
    module.linkLibrary(sdl_dep.artifact("SDL3"));
    return module;
}

fn createFreetypeModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const freetype_dep = b.dependency("freetype", .{
        .target = target,
        .optimize = optimize,
    });
    const freetype_artifact = freetype_dep.artifact("freetype");

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c/freetype.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(freetype_dep.path("include"));

    const module = translate_c.createModule();
    module.linkLibrary(freetype_artifact);
    return module;
}

fn compileShader(
    b: *std.Build,
    name: []const u8,
    stage: []const u8,
) std.Build.LazyPath {
    const src_path = b.path(b.fmt("src/shaders/{s}.{s}.glsl", .{ name, stage }));
    const out_filename = b.fmt("{s}.{s}.spv", .{ name, stage });

    const cmd = b.addSystemCommand(&.{
        "glslc",
        b.fmt("-fshader-stage={s}", .{stage}),
        "-O",
        "-o",
    });
    const out = cmd.addOutputFileArg(out_filename);
    cmd.addFileArg(src_path);
    return out;
}

fn createShadersModule(b: *std.Build) *std.Build.Module {
    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(compileShader(b, "solid", "vert"), "solid.vert.spv");
    _ = wf.addCopyFile(compileShader(b, "solid", "frag"), "solid.frag.spv");
    _ = wf.addCopyFile(compileShader(b, "textured", "vert"), "textured.vert.spv");
    _ = wf.addCopyFile(compileShader(b, "textured", "frag"), "textured.frag.spv");

    const root = wf.add("shaders.zig",
        \\pub const solid_vert = @embedFile("solid.vert.spv");
        \\pub const solid_frag = @embedFile("solid.frag.spv");
        \\pub const textured_vert = @embedFile("textured.vert.spv");
        \\pub const textured_frag = @embedFile("textured.frag.spv");
        \\
    );

    return b.createModule(.{ .root_source_file = root });
}
