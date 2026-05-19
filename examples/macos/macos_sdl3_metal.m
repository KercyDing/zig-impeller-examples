#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

void* macosSdl3ConfigureMetalLayer(void* layer_ptr) {
    if (layer_ptr == NULL) {
        return NULL;
    }
    CAMetalLayer* layer = (__bridge CAMetalLayer*)layer_ptr;
    layer.framebufferOnly = NO;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    if (layer.device == nil) {
        layer.device = MTLCreateSystemDefaultDevice();
    }
    if (layer.device == nil) {
        return NULL;
    }
    return layer_ptr;
}

void* macosSdl3AcquireNextDrawable(void* layer_ptr, double width, double height) {
    if (layer_ptr == NULL) {
        return NULL;
    }
    @autoreleasepool {
        CAMetalLayer* layer = (__bridge CAMetalLayer*)layer_ptr;
        if (width > 0.0 && height > 0.0) {
            layer.drawableSize = CGSizeMake(width, height);
        }
        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (drawable == nil) {
            return NULL;
        }
        return (__bridge_retained void*)drawable;
    }
}

void macosSdl3ReleaseDrawable(void* drawable_ptr) {
    if (drawable_ptr == NULL) {
        return;
    }
    id drawable = (__bridge_transfer id)drawable_ptr;
    (void)drawable;
}
