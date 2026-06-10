const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl_mod = createSdlModule(b, target, optimize);
    const freetype_mod = createFreetypeModule(b, target, optimize);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("sdl", sdl_mod);
    exe_mod.addImport("freetype", freetype_mod);

    const exe = b.addExecutable(.{
        .name = "ui_framework",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");

    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

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
