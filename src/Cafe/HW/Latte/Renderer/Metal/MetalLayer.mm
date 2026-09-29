#include "Cafe/HW/Latte/Renderer/Metal/MetalLayer.h"

#if CEMU_IOS

#import <QuartzCore/CAMetalLayer.h>

// On iPadOS the UIKit frontend owns the view hierarchy and creates the CAMetalLayer on the main thread.
// WindowHandleInfo::surface points directly at that layer.
void* CreateMetalLayer(void* handle, float& scaleX, float& scaleY)
{
	CAMetalLayer* layer = (__bridge CAMetalLayer*)handle;

	scaleX = (float)layer.contentsScale;
	scaleY = (float)layer.contentsScale;

	// balanced by the release in ~MetalLayerHandle
	CFRetain((__bridge CFTypeRef)layer);
	return (__bridge void*)layer;
}

#else

#include "Cafe/HW/Latte/Renderer/MetalView.h"

void* CreateMetalLayer(void* handle, float& scaleX, float& scaleY)
{
	NSView* view = (NSView*)handle;

	MetalView* childView = [[MetalView alloc] initWithFrame:view.bounds];
	childView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	childView.wantsLayer = YES;

	[view addSubview:childView];

	const NSRect points = [childView frame];
    const NSRect pixels = [childView convertRectToBacking:points];

	scaleX = (float)(pixels.size.width / points.size.width);
    scaleY = (float)(pixels.size.height / points.size.height);

	return childView.layer;
}

#endif
