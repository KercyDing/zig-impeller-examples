# zig-impeller-examples

Runnable GLFW examples for [`zig-impeller`](https://github.com/KercyDing/zig-impeller).

## Dependencies

This package depends on:

- `zig_impeller`
- `glfw_zig`

## Run

Linux defaults to X11:

```bash
zig build run -Dplatform=linux
```

Use Wayland explicitly when needed:

```bash
zig build run -Dplatform=linux -Dwm=wayland
```

macOS:

```bash
zig build run -Dplatform=macos
```

Windows:

```bash
zig build run -Dplatform=windows
```

## Known issue

`zig build run` may print Vulkan swapchain validation errors. This comes from the current Impeller SDK, not these examples, and may be fixed by a future SDK update.
