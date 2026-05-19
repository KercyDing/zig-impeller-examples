const std = @import("std");

const Backend = enum { glfw, sdl3 };

const ExampleInfo = struct {
    name: []const u8,
    src: []const u8,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const os_tag = target.result.os.tag;
    const backend = b.option(Backend, "backend", "Window backend (sdl3, glfw)") orelse .sdl3;

    const impeller_dep = b.dependency("zig_impeller", .{
        .target = target,
        .optimize = optimize,
    });
    const impeller_mod = impeller_dep.module("impeller");

    const common_draw_mod = b.createModule(.{
        .root_source_file = b.path("examples/common/draw.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "impeller", .module = impeller_mod },
        },
    });

    const example_info: ExampleInfo = switch (backend) {
        .glfw => switch (os_tag) {
            .linux => .{ .name = "linux-glfw", .src = "examples/linux/linux_glfw.zig" },
            .macos => .{ .name = "macos-glfw", .src = "examples/macos/macos_glfw.zig" },
            .windows => .{ .name = "windows-glfw", .src = "examples/windows/windows_glfw.zig" },
            else => @panic("Unsupported OS for GLFW examples"),
        },
        .sdl3 => switch (os_tag) {
            .linux => .{ .name = "linux-sdl3", .src = "examples/linux/linux_sdl3.zig" },
            .macos => .{ .name = "macos-sdl3", .src = "examples/macos/macos_sdl3.zig" },
            .windows => .{ .name = "windows-sdl3", .src = "examples/windows/windows_sdl3.zig" },
            else => @panic("Unsupported OS for SDL3 examples"),
        },
    };

    const exe_mod = b.createModule(.{
        .root_source_file = b.path(example_info.src),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("impeller", impeller_mod);
    exe_mod.addImport("common_draw", common_draw_mod);

    switch (backend) {
        .glfw => {
            const glfw_dep = b.lazyDependency("glfw_zig", .{
                .target = target,
                .optimize = optimize,
            }) orelse return;
            const glfw_lib = glfw_dep.artifact("glfw");

            const glfw_translate = b.addTranslateC(.{
                .root_source_file = glfw_dep.path("glfw/include/GLFW/glfw3.h"),
                .target = target,
                .optimize = optimize,
            });
            if (os_tag == .linux or os_tag == .windows) {
                glfw_translate.defineCMacro("GLFW_INCLUDE_VULKAN", null);
                glfw_translate.addIncludePath(glfw_lib.getEmittedIncludeTree());
            }

            exe_mod.addImport("glfw_c", glfw_translate.createModule());
            exe_mod.linkLibrary(glfw_lib);
        },
        .sdl3 => {
            const sdl3_dep = b.lazyDependency("sdl3", .{
                .target = target,
                .optimize = optimize,
            }) orelse return;
            exe_mod.addImport("sdl3", sdl3_dep.module("sdl3"));
        },
    }

    const exe = b.addExecutable(.{
        .name = example_info.name,
        .root_module = exe_mod,
        .use_llvm = if (os_tag == .macos) null else true,
        .use_lld = if (os_tag == .macos) null else true,
    });

    exe.root_module.linkLibrary(impeller_dep.artifact("impeller"));

    switch (os_tag) {
        .macos => {
            const metal_file = switch (backend) {
                .glfw => "examples/macos/macos_glfw_metal.m",
                .sdl3 => "examples/macos/macos_sdl3_metal.m",
            };
            exe.root_module.addCSourceFile(.{
                .file = b.path(metal_file),
                .flags = &.{ "-fobjc-arc", "-Wno-deprecated-declarations", "-Wno-unguarded-availability-new" },
                .language = .objective_c,
            });
            exe.root_module.linkFramework("AppKit", .{});
            exe.root_module.linkFramework("Metal", .{});
            exe.root_module.linkFramework("QuartzCore", .{});
        },
        .linux => {
            exe.root_module.linkSystemLibrary("vulkan", .{});
            exe.root_module.linkSystemLibrary("dl", .{});
            exe.root_module.linkSystemLibrary("pthread", .{});
            exe.root_module.linkSystemLibrary("m", .{});
        },
        .windows => {
            const dll = b.addInstallBinFile(impeller_dep.namedLazyPath("impeller_library"), "impeller.dll");
            b.getInstallStep().dependOn(&dll.step);
        },
        else => {},
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the selected example");
    run_step.dependOn(&run_cmd.step);
}
