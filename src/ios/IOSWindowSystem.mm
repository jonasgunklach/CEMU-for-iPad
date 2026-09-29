// WindowSystem implementation for the iPadOS frontend (replaces wxWindowSystem.cpp)

#import <UIKit/UIKit.h>

// Objective-C++ sources do not use the precompiled header
#include "Common/precompiled.h"

#include "gui/interface/WindowSystem.h"
#include "Cafe/CafeSystem.h"

WindowSystem::WindowInfo g_window_info{};

static UIViewController* TopViewController()
{
	UIWindowScene* scene = nil;
	for (UIScene* s in UIApplication.sharedApplication.connectedScenes)
	{
		if ([s isKindOfClass:UIWindowScene.class])
		{
			scene = (UIWindowScene*)s;
			break;
		}
	}
	UIViewController* vc = scene.keyWindow.rootViewController;
	while (vc.presentedViewController)
		vc = vc.presentedViewController;
	return vc;
}

void WindowSystem::Create()
{
	// the UIKit application lifecycle is started from main.mm
}

void WindowSystem::ShowErrorDialog(std::string_view message, std::string_view title, std::optional<WindowSystem::ErrorCategory> /*errorCategory*/)
{
	cemuLog_log(LogType::Force, "{}: {}", title, message);
	NSString* nsTitle = title.empty() ? @"Error" : [[NSString alloc] initWithBytes:title.data() length:title.size() encoding:NSUTF8StringEncoding];
	NSString* nsMessage = [[NSString alloc] initWithBytes:message.data() length:message.size() encoding:NSUTF8StringEncoding];
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertController* alert = [UIAlertController alertControllerWithTitle:nsTitle message:nsMessage preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
		[TopViewController() presentViewController:alert animated:YES completion:nil];
	});
}

WindowSystem::WindowInfo& WindowSystem::GetWindowInfo()
{
	return g_window_info;
}

void WindowSystem::UpdateWindowTitles(bool isIdle, bool isLoading, double fps)
{
	// there are no window titles on iPadOS, FPS is shown by the Cemu overlay
}

void WindowSystem::GetWindowSize(int& w, int& h)
{
	w = g_window_info.width;
	h = g_window_info.height;
}

void WindowSystem::GetPadWindowSize(int& w, int& h)
{
	if (g_window_info.pad_open)
	{
		w = g_window_info.pad_width;
		h = g_window_info.pad_height;
	}
	else
	{
		w = 0;
		h = 0;
	}
}

void WindowSystem::GetWindowPhysSize(int& w, int& h)
{
	w = g_window_info.phys_width;
	h = g_window_info.phys_height;
}

void WindowSystem::GetPadWindowPhysSize(int& w, int& h)
{
	if (g_window_info.pad_open)
	{
		w = g_window_info.phys_pad_width;
		h = g_window_info.phys_pad_height;
	}
	else
	{
		w = 0;
		h = 0;
	}
}

double WindowSystem::GetWindowDPIScale()
{
	return g_window_info.dpi_scale;
}

double WindowSystem::GetPadDPIScale()
{
	return g_window_info.pad_open ? g_window_info.pad_dpi_scale.load() : 1.0;
}

bool WindowSystem::IsPadWindowOpen()
{
	return g_window_info.pad_open;
}

bool WindowSystem::IsKeyDown(uint32 key)
{
	return g_window_info.get_keystate(key);
}

bool WindowSystem::IsKeyDown(PlatformKeyCodes platformKey)
{
	// hardware keyboard key codes use UIKeyboardHIDUsage values
	uint32 key = 0;
	switch (platformKey)
	{
	case PlatformKeyCodes::LCONTROL:
		key = UIKeyboardHIDUsageKeyboardLeftControl;
		break;
	case PlatformKeyCodes::RCONTROL:
		key = UIKeyboardHIDUsageKeyboardRightControl;
		break;
	case PlatformKeyCodes::TAB:
		key = UIKeyboardHIDUsageKeyboardTab;
		break;
	case PlatformKeyCodes::ESCAPE:
		key = UIKeyboardHIDUsageKeyboardEscape;
		break;
	default:
		return false;
	}
	return WindowSystem::IsKeyDown(key);
}

std::string WindowSystem::GetKeyCodeName(uint32 key)
{
	return fmt::format("key_{}", key);
}

bool WindowSystem::InputConfigWindowHasFocus()
{
	return false;
}

void WindowSystem::NotifyGameLoaded()
{
}

void WindowSystem::NotifyGameExited()
{
}

void WindowSystem::RefreshGameList()
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSNotificationCenter.defaultCenter postNotificationName:@"CemuRefreshGameList" object:nil];
	});
}

bool WindowSystem::IsFullScreen()
{
	return g_window_info.is_fullscreen;
}

void WindowSystem::CaptureInput(const ControllerState& currentState, const ControllerState& lastState)
{
	// hotkeys are not supported yet on iPadOS
}
