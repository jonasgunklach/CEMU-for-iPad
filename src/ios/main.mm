#import <UIKit/UIKit.h>

#import "CemuAppDelegate.h"

#ifdef HAS_SDL
#define SDL_MAIN_HANDLED
#include <SDL3/SDL_main.h>
#endif

int main(int argc, char* argv[])
{
#ifdef HAS_SDL
	// UIKit owns the application lifecycle, SDL is only used for game controllers
	SDL_SetMainReady();
#endif
	@autoreleasepool
	{
		return UIApplicationMain(argc, argv, nil, NSStringFromClass(CemuAppDelegate.class));
	}
}
