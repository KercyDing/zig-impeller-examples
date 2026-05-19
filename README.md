# zig-impeller-examples

Runnable SDL3 and GLFW examples for [`zig-impeller`](https://github.com/KercyDing/zig-impeller).

## Dependencies

This package depends on:

- `zig_impeller`
- `sdl3`
- `glfw_zig`

## Run

Run on the current machine:

```bash
zig build run
```

SDL3 is the default backend.

Use GLFW instead:

```bash
zig build run -Dbackend=glfw
```

The SDL3 Linux example forces the X11 video driver for now.

Cross compile with Zig's standard target option. For example, Linux to Windows:

```bash
zig build -Dtarget=x86_64-windows-gnu
```

Available Impeller SDK targets:

| Platform | `-Dtarget` |
| --- | --- |
| Linux x64 | `x86_64-linux-gnu` |
| Linux arm64 | `aarch64-linux-gnu` |
| macOS x64 | `x86_64-macos` |
| macOS arm64 | `aarch64-macos` |
| Windows x64 | `x86_64-windows-gnu` |
| Windows arm64 | `aarch64-windows-gnu` |

These examples also build SDL3/GLFW and platform windowing code, so not every SDK target can be cross compiled from every host. macOS targets need Apple's SDK/frameworks, and Linux arm64 currently needs extra windowing cross-build support.

## Known issue

`zig build run` may print Vulkan swapchain validation errors. This comes from the current Impeller SDK, not these examples, and may be fixed by a future SDK update.
