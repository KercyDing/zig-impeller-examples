const std = @import("std");

const BuildOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    platform: Platform,
    linux_wm: LinuxWindowManager,
};

const Platform = enum {
    linux,
    macos,
    windows,
};

const LinuxWindowManager = enum {
    x11,
    wayland,
};

const ExampleConfig = struct {
    name: []const u8,
    source: []const u8,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options: BuildOptions = .{
        .target = target,
        .optimize = optimize,
        .platform = b.option(Platform, "platform", "Example platform to build (linux, macos, windows)") orelse defaultPlatform(b.graph.host.result.os.tag),
        .linux_wm = b.option(LinuxWindowManager, "wm", "Linux window manager backend (x11, wayland)") orelse .x11,
    };

    const impeller_dep = b.dependency("zig_impeller", .{
        .target = target,
        .optimize = optimize,
    });
    const glfw_dep = b.dependency("glfw_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const impeller = impeller_dep.module("impeller");
    const glfw_lib = glfw_dep.artifact("glfw");
    const glfw_c = addGlfwBindings(b, options, glfw_dep, glfw_lib, options.platform);
    const example_options = b.addOptions();
    example_options.addOption(LinuxWindowManager, "wm", options.linux_wm);

    const config = exampleConfig(options);
    const example_mod = b.createModule(.{
        .root_source_file = b.path(config.source),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "impeller", .module = impeller },
            .{ .name = "common_draw", .module = addCommonDrawModule(b, options, impeller_dep, impeller) },
            .{ .name = "glfw_c", .module = glfw_c },
            .{ .name = "build_options", .module = example_options.createModule() },
        },
    });
    configureImpeller(example_mod, impeller_dep);
    configurePlatformModule(b, example_mod, options);

    const example = b.addExecutable(.{
        .name = config.name,
        .root_module = example_mod,
        .use_llvm = if (options.platform == .macos) null else true,
        .use_lld = if (options.platform == .macos) null else true,
    });
    example.root_module.linkLibrary(glfw_lib);
    configurePlatformExecutable(b, example, options, impeller_dep);

    b.installArtifact(example);

    const run_example = b.addRunArtifact(example);
    configureImpellerRuntime(run_example, impeller_dep, target.result);
    if (b.args) |args| {
        run_example.addArgs(args);
    }

    const run_step = b.step("run", "Run the selected GLFW example");
    run_step.dependOn(&run_example.step);
}

fn exampleConfig(options: BuildOptions) ExampleConfig {
    return switch (options.platform) {
        .linux => blk: {
            if (options.target.result.os.tag != .linux or options.target.result.cpu.arch != .x86_64) {
                @panic("-Dplatform=linux requires a linux x86_64 target");
            }
            break :blk .{ .name = "linux-glfw", .source = "examples/linux/linux_glfw.zig" };
        },
        .macos => blk: {
            if (options.target.result.os.tag != .macos) {
                @panic("-Dplatform=macos requires a macOS target");
            }
            break :blk .{ .name = "macos-glfw", .source = "examples/macos/macos_glfw.zig" };
        },
        .windows => blk: {
            if (options.target.result.os.tag != .windows) {
                @panic("-Dplatform=windows requires a windows target");
            }
            if (options.target.result.cpu.arch != .x86_64 and options.target.result.cpu.arch != .aarch64) {
                @panic("-Dplatform=windows requires an x86_64 or aarch64 target");
            }
            break :blk .{ .name = "windows-glfw", .source = "examples/windows/windows_glfw.zig" };
        },
    };
}

fn configurePlatformModule(b: *std.Build, module: *std.Build.Module, options: BuildOptions) void {
    if (options.platform != .macos) return;

    module.addCSourceFile(.{
        .file = b.path("examples/macos/macos_glfw_metal.m"),
        .flags = &.{ "-fobjc-arc", "-Wno-deprecated-declarations", "-Wno-unguarded-availability-new" },
        .language = .objective_c,
    });
    module.linkFramework("AppKit", .{});
    module.linkFramework("Metal", .{});
    module.linkFramework("QuartzCore", .{});
}

fn configurePlatformExecutable(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    options: BuildOptions,
    impeller_dep: *std.Build.Dependency,
) void {
    switch (options.platform) {
        .linux => linkLinuxVulkanExample(exe),
        .macos => {},
        .windows => installImpellerRuntimeDll(b, impeller_dep, options.target.result),
    }
}

fn defaultPlatform(os_tag: std.Target.Os.Tag) Platform {
    return switch (os_tag) {
        .macos => .macos,
        .windows => .windows,
        else => .linux,
    };
}

fn addCommonDrawModule(
    b: *std.Build,
    options: BuildOptions,
    impeller_dep: *std.Build.Dependency,
    impeller: *std.Build.Module,
) *std.Build.Module {
    const draw_mod = b.createModule(.{
        .root_source_file = b.path("examples/common/draw.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "impeller", .module = impeller },
        },
    });
    configureImpeller(draw_mod, impeller_dep);
    return draw_mod;
}

fn addGlfwBindings(
    b: *std.Build,
    options: BuildOptions,
    glfw_dep: *std.Build.Dependency,
    glfw_lib: *std.Build.Step.Compile,
    platform: Platform,
) *std.Build.Module {
    const translate = b.addTranslateC(.{
        .root_source_file = glfw_dep.path("glfw/include/GLFW/glfw3.h"),
        .target = options.target,
        .optimize = options.optimize,
    });
    if (platform == .linux or platform == .windows) {
        translate.defineCMacro("GLFW_INCLUDE_VULKAN", null);
        translate.addIncludePath(glfw_lib.getEmittedIncludeTree());
    }
    return translate.createModule();
}

fn linkLinuxVulkanExample(exe: *std.Build.Step.Compile) void {
    exe.root_module.linkSystemLibrary("vulkan", .{});
    exe.root_module.linkSystemLibrary("dl", .{});
    exe.root_module.linkSystemLibrary("pthread", .{});
    exe.root_module.linkSystemLibrary("m", .{});
}

fn configureImpeller(module: *std.Build.Module, impeller_dep: *std.Build.Dependency) void {
    module.addIncludePath(impeller_dep.path("vendor/impeller/include"));
}

fn configureImpellerRuntime(run: *std.Build.Step.Run, impeller_dep: *std.Build.Dependency, target: std.Target) void {
    const lib_path_string = impellerLibPathString(impeller_dep, target);
    run.setEnvironmentVariable("DYLD_LIBRARY_PATH", lib_path_string);
    run.setEnvironmentVariable("LD_LIBRARY_PATH", lib_path_string);
    run.addPathDir(lib_path_string);
}

fn installImpellerRuntimeDll(b: *std.Build, impeller_dep: *std.Build.Dependency, target: std.Target) void {
    if (target.os.tag != .windows) return;
    const install = b.addInstallBinFile(impellerLibraryPath(impeller_dep, target), "impeller.dll");
    b.getInstallStep().dependOn(&install.step);
}

fn impellerLibraryPath(dep: *std.Build.Dependency, target: std.Target) std.Build.LazyPath {
    return dep.path(dep.builder.fmt("vendor/impeller/lib/{s}/{s}/{s}", .{
        impellerLibOsDir(target) orelse @panic("unsupported Impeller SDK target"),
        impellerLibArchDir(target) orelse @panic("unsupported Impeller SDK target architecture"),
        impellerLibraryName(target),
    }));
}

fn impellerLibPath(dep: *std.Build.Dependency, target: std.Target) std.Build.LazyPath {
    return dep.path(dep.builder.fmt("vendor/impeller/lib/{s}/{s}", .{
        impellerLibOsDir(target) orelse @panic("unsupported Impeller SDK target"),
        impellerLibArchDir(target) orelse @panic("unsupported Impeller SDK target architecture"),
    }));
}

fn impellerLibPathString(dep: *std.Build.Dependency, target: std.Target) []const u8 {
    return dep.builder.pathFromRoot(dep.builder.fmt("vendor/impeller/lib/{s}/{s}", .{
        impellerLibOsDir(target) orelse @panic("unsupported Impeller SDK target"),
        impellerLibArchDir(target) orelse @panic("unsupported Impeller SDK target architecture"),
    }));
}

fn impellerLibraryName(target: std.Target) []const u8 {
    return switch (target.os.tag) {
        .macos => "libimpeller.dylib",
        .windows => "impeller.dll",
        else => "libimpeller.so",
    };
}

fn impellerLibOsDir(target: std.Target) ?[]const u8 {
    return switch (target.os.tag) {
        .macos => "macos",
        .linux => "linux",
        .windows => "windows",
        else => null,
    };
}

fn impellerLibArchDir(target: std.Target) ?[]const u8 {
    return switch (target.cpu.arch) {
        .aarch64 => "arm64",
        .x86_64 => "x64",
        else => null,
    };
}
