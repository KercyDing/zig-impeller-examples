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
    const example = addExample(b, options, impeller_dep, impeller, glfw_dep);
    const run_example = b.addRunArtifact(example);
    configureImpellerRuntime(run_example, impeller_dep, target.result);

    const run_step = b.step("run", "Run the selected GLFW example");
    run_step.dependOn(&run_example.step);
}

fn addExample(
    b: *std.Build,
    options: BuildOptions,
    impeller_dep: *std.Build.Dependency,
    impeller: *std.Build.Module,
    glfw_dep: *std.Build.Dependency,
) *std.Build.Step.Compile {
    return switch (options.platform) {
        .linux => addLinuxGlfwExample(b, options, impeller_dep, impeller, glfw_dep),
        .macos => addMacosGlfwExample(b, options, impeller_dep, impeller, glfw_dep),
        .windows => addWindowsGlfwExample(b, options, impeller_dep, impeller, glfw_dep),
    };
}

fn addLinuxGlfwExample(
    b: *std.Build,
    options: BuildOptions,
    impeller_dep: *std.Build.Dependency,
    impeller: *std.Build.Module,
    glfw_dep: *std.Build.Dependency,
) *std.Build.Step.Compile {
    if (options.target.result.os.tag != .linux or options.target.result.cpu.arch != .x86_64) {
        @panic("-Dplatform=linux requires a linux x86_64 target");
    }

    const glfw_lib = glfw_dep.artifact("glfw");
    const glfw_c = addGlfwBindings(b, options, glfw_dep, glfw_lib, .linux);
    const linux_example_options = b.addOptions();
    linux_example_options.addOption(LinuxWindowManager, "wm", options.linux_wm);

    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/linux/linux_glfw.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "impeller", .module = impeller },
            .{ .name = "common_draw", .module = addCommonDrawModule(b, options, impeller_dep, impeller) },
            .{ .name = "glfw_c", .module = glfw_c },
            .{ .name = "build_options", .module = linux_example_options.createModule() },
        },
    });
    configureImpeller(example_mod, impeller_dep);

    const example = b.addExecutable(.{
        .name = "linux-glfw",
        .root_module = example_mod,
        .use_llvm = true,
        .use_lld = true,
    });
    example.root_module.linkLibrary(glfw_lib);
    linkLinuxVulkanExample(example);
    return example;
}

fn addMacosGlfwExample(
    b: *std.Build,
    options: BuildOptions,
    impeller_dep: *std.Build.Dependency,
    impeller: *std.Build.Module,
    glfw_dep: *std.Build.Dependency,
) *std.Build.Step.Compile {
    if (options.target.result.os.tag != .macos) {
        @panic("-Dplatform=macos requires a macOS target");
    }

    const glfw_lib = glfw_dep.artifact("glfw");
    const glfw_c = addGlfwBindings(b, options, glfw_dep, glfw_lib, .macos);

    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/macos/macos_glfw.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "impeller", .module = impeller },
            .{ .name = "common_draw", .module = addCommonDrawModule(b, options, impeller_dep, impeller) },
            .{ .name = "glfw_c", .module = glfw_c },
        },
    });
    configureImpeller(example_mod, impeller_dep);
    example_mod.addCSourceFile(.{
        .file = b.path("examples/macos/macos_glfw_metal.m"),
        .flags = &.{ "-fobjc-arc", "-Wno-deprecated-declarations", "-Wno-unguarded-availability-new" },
        .language = .objective_c,
    });
    example_mod.linkFramework("AppKit", .{});
    example_mod.linkFramework("Metal", .{});
    example_mod.linkFramework("QuartzCore", .{});

    const example = b.addExecutable(.{
        .name = "macos-glfw",
        .root_module = example_mod,
    });
    example.root_module.linkLibrary(glfw_lib);
    return example;
}

fn addWindowsGlfwExample(
    b: *std.Build,
    options: BuildOptions,
    impeller_dep: *std.Build.Dependency,
    impeller: *std.Build.Module,
    glfw_dep: *std.Build.Dependency,
) *std.Build.Step.Compile {
    if (options.target.result.os.tag != .windows) {
        @panic("-Dplatform=windows requires a windows target");
    }
    if (options.target.result.cpu.arch != .x86_64 and options.target.result.cpu.arch != .aarch64) {
        @panic("-Dplatform=windows requires an x86_64 or aarch64 target");
    }

    const glfw_lib = glfw_dep.artifact("glfw");
    const glfw_c = addGlfwBindings(b, options, glfw_dep, glfw_lib, .windows);

    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/windows/windows_glfw.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "impeller", .module = impeller },
            .{ .name = "common_draw", .module = addCommonDrawModule(b, options, impeller_dep, impeller) },
            .{ .name = "glfw_c", .module = glfw_c },
        },
    });
    configureImpeller(example_mod, impeller_dep);

    const example = b.addExecutable(.{
        .name = "windows-glfw",
        .root_module = example_mod,
        .use_llvm = true,
        .use_lld = true,
    });
    example.root_module.linkLibrary(glfw_lib);
    installImpellerRuntimeDll(b, impeller_dep, options.target.result);
    return example;
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

fn linkImpeller(module: *std.Build.Module, impeller_dep: *std.Build.Dependency, target: std.Target) void {
    if (target.os.tag == .windows) {
        module.addObjectFile(impellerImportLibraryPath(impeller_dep, target));
    } else {
        module.addObjectFile(impellerLibraryPath(impeller_dep, target));
    }
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

fn impellerImportLibraryPath(dep: *std.Build.Dependency, target: std.Target) std.Build.LazyPath {
    return dep.path(dep.builder.fmt("vendor/impeller/lib/{s}/{s}/{s}", .{
        impellerLibOsDir(target) orelse @panic("unsupported Impeller SDK target"),
        impellerLibArchDir(target) orelse @panic("unsupported Impeller SDK target architecture"),
        impellerImportLibraryName(),
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

fn impellerImportLibraryName() []const u8 {
    return "impeller.dll.lib";
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
