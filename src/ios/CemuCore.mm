#import "CemuCore.h"
#import <AVFoundation/AVFoundation.h>

// Objective-C++ sources do not use the precompiled header
#include "Common/precompiled.h"

#include "Cafe/CafeSystem.h"
#include "Cafe/TitleList/TitleList.h"
#include "Cafe/TitleList/TitleInfo.h"
#include "Cafe/HW/Latte/Core/LatteOverlay.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalRenderer.h"
#include "Cemu/ncrypto/ncrypto.h"
#include "config/ActiveSettings.h"
#include "config/CemuConfig.h"
#include "config/NetworkSettings.h"
#include "gui/interface/WindowSystem.h"
#include "input/InputManager.h"
#include "audio/IAudioAPI.h"
#include "input/emulated/VPADController.h"
#include "input/api/Controller.h"
#include "Cafe/HW/Latte/Core/Latte.h"
#ifdef HAS_SDL
#include "input/api/SDL/SDLControllerProvider.h"
#endif

#include <boost/algorithm/string/predicate.hpp>

// from main.cpp
void CemuCommonInit();

@implementation CemuTitle
@end

static std::atomic_bool s_initialized = false;
static NSTimer* s_sdlPumpTimer = nil;

static fs::path ToPath(NSURL* url)
{
	return _utf8ToPath(url.fileSystemRepresentation);
}

static bool CreateDirectoriesIfNotExist(const fs::path& path)
{
	std::error_code ec;
	if (!fs::exists(path, ec))
		return fs::create_directories(path, ec);
	return true;
}

// mirrors CemuApp::CreateDefaultMLCFiles from the wx frontend
static bool CreateDefaultMLCFiles(const fs::path& mlc)
{
	const fs::path directories[] = {
		mlc,
		mlc / "sys",
		mlc / "usr",
		mlc / "usr/title/00050000", // base
		mlc / "usr/title/0005000c", // dlc
		mlc / "usr/title/0005000e", // update
		mlc / "usr/save/00050010/1004a000/user/common/db", // Mii Maker save folders
		mlc / "usr/save/00050010/1004a100/user/common/db",
		mlc / "usr/save/00050010/1004a200/user/common/db",
		mlc / "sys/title/0005001b/1005c000/content" // lang files
	};
	for (auto& path : directories)
	{
		if (!CreateDirectoriesIfNotExist(path))
			return false;
	}
	try
	{
		const auto langDir = mlc / "sys/title/0005001b/1005c000/content";
		auto langFile = langDir / "language.txt";
		if (!fs::exists(langFile))
		{
			std::ofstream file(langFile);
			const char* langStrings[] = {"ja", "en", "fr", "de", "it", "es", "zh", "ko", "nl", "pt", "ru", "zh"};
			for (const char* lang : langStrings)
				file << fmt::format(R"("{}",)", lang) << std::endl;
		}
		auto countryFile = langDir / "country.txt";
		if (!fs::exists(countryFile))
		{
			std::ofstream file(countryFile);
			for (sint32 i = 0; i < NCrypto::GetCountryCount(); i++)
			{
				const char* countryCode = NCrypto::GetCountryAsString(i);
				if (boost::iequals(countryCode, "NN"))
					file << "NULL," << std::endl;
				else
					file << fmt::format(R"("{}",)", countryCode) << std::endl;
			}
		}
	}
	catch (const std::exception& ex)
	{
		cemuLog_log(LogType::Force, "Failed to create default MLC files: {}", ex.what());
		return false;
	}
	return true;
}

static void DeterminePaths()
{
	NSFileManager* fm = NSFileManager.defaultManager;
	NSURL* caches = [[fm URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"Cemu"];

	fs::path exePath = _utf8ToPath(NSBundle.mainBundle.executablePath.fileSystemRepresentation);
	fs::path userDataPath = ToPath(CemuCore.documentsURL);
	fs::path cachePath = ToPath(caches);
	// gameProfiles/ and resources/ are shipped inside the app bundle
	fs::path dataPath = _utf8ToPath(NSBundle.mainBundle.resourcePath.fileSystemRepresentation) / "CemuData";

	std::set<fs::path> failedWriteAccess;
	ActiveSettings::SetPaths(false, exePath, userDataPath, userDataPath, cachePath, dataPath, failedWriteAccess);
	for (auto& path : failedWriteAccess)
		cemuLog_log(LogType::Force, "No write access to {}", _pathToUtf8(path));
}

@implementation CemuCore

+ (NSURL*)documentsURL
{
	return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
}

+ (NSURL*)gamesURL
{
	return [self.documentsURL URLByAppendingPathComponent:@"games" isDirectory:YES];
}

+ (BOOL)isInitialized
{
	return s_initialized;
}

+ (void)initializeWithCompletion:(void (^)(void))completion
{
	if (s_initialized)
	{
		completion();
		return;
	}

	SetThreadName("MainThread_UI");
	// security-scoped folders must be re-opened before the first title scan
	[self restoreGameFolderAccess];
	DeterminePaths();
	CreateDirectoriesIfNotExist(ToPath(self.gamesURL));
	CreateDirectoriesIfNotExist(ActiveSettings::GetConfigPath("controllerProfiles"));

	GetConfigHandle().SetFilename(ActiveSettings::GetConfigPath("settings.xml").generic_wstring());
	std::error_code ec;
	const bool isFirstStart = !fs::exists(ActiveSettings::GetConfigPath("settings.xml"), ec);
	NetworkConfig::LoadOnce();
	if (isFirstStart)
	{
		// Documents/games is always scanned
		GetConfig().game_paths.emplace_back(_pathToUtf8(ToPath(self.gamesURL)));
		GetConfigHandle().Save();
	}
	else
		GetConfigHandle().Load();
	// CoreAudio is the only audio backend on iPadOS. Persist it since CemuCommonInit() reloads settings.xml
	if (GetConfig().audio_api != IAudioAPI::CoreAudio)
	{
		GetConfig().audio_api = IAudioAPI::CoreAudio;
		GetConfigHandle().Save();
	}
	[AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionMixWithOthers error:nil];
	[AVAudioSession.sharedInstance setActive:YES error:nil];

	if (!CreateDefaultMLCFiles(ActiveSettings::GetMlcPath()))
		WindowSystem::ShowErrorDialog("Cemu failed to create the mlc directory.", "Error");

	ActiveSettings::Init();
	LatteOverlay_init();

#ifdef HAS_SDL
	// like on macOS, SDL events are pumped from the main thread
	SDLControllerProvider::InitSDL();
	s_sdlPumpTimer = [NSTimer scheduledTimerWithTimeInterval:0.005 repeats:YES block:^(NSTimer*) {
		SDLControllerProvider::PumpSDLEvents();
	}];
#endif

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		CemuCommonInit();
		CafeTitleList::WaitForMandatoryScan();
		s_initialized = true;
		dispatch_async(dispatch_get_main_queue(), completion);
	});
}

+ (void)refreshTitlesWithCompletion:(void (^)(void))completion
{
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		CafeTitleList::ClearScanPaths();
		for (auto& it : GetConfig().game_paths)
			CafeTitleList::AddScanPath(_utf8ToPath(it));
		CafeTitleList::Refresh();
		while (CafeTitleList::IsScanning())
			std::this_thread::sleep_for(std::chrono::milliseconds(50));
		dispatch_async(dispatch_get_main_queue(), completion);
	});
}

+ (NSArray<CemuTitle*>*)titles
{
	NSMutableArray<CemuTitle*>* result = [NSMutableArray array];
	for (TitleId titleId : CafeTitleList::GetAllTitleIds())
	{
		TitleIdParser parser(titleId);
		if (parser.GetType() != TitleIdParser::TITLE_TYPE::BASE_TITLE && parser.GetType() != TitleIdParser::TITLE_TYPE::BASE_TITLE_DEMO)
			continue;
		TitleInfo info;
		if (!CafeTitleList::GetFirstByTitleId(titleId, info))
			continue;
		CemuTitle* title = [CemuTitle new];
		title.titleId = titleId;
		title.version = info.GetAppTitleVersion();
		title.name = [NSString stringWithUTF8String:info.GetMetaTitleName().c_str()] ?: @"Unknown";
		title.path = [NSString stringWithUTF8String:_pathToUtf8(info.GetPath()).c_str()];
		[result addObject:title];
	}
	[result sortUsingComparator:^NSComparisonResult(CemuTitle* a, CemuTitle* b) {
		return [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	return result;
}

+ (void)addGameFolder:(NSURL*)url
{
	// keep access to the folder across launches
	NSData* bookmark = [url bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:nil];
	if (bookmark)
	{
		NSMutableArray* bookmarks = [[NSUserDefaults.standardUserDefaults arrayForKey:@"gameFolderBookmarks"] mutableCopy] ?: [NSMutableArray array];
		[bookmarks addObject:bookmark];
		[NSUserDefaults.standardUserDefaults setObject:bookmarks forKey:@"gameFolderBookmarks"];
	}
	[url startAccessingSecurityScopedResource];
	std::string path = _pathToUtf8(ToPath(url));
	auto& gamePaths = GetConfig().game_paths;
	if (std::find(gamePaths.begin(), gamePaths.end(), path) == gamePaths.end())
	{
		gamePaths.emplace_back(path);
		GetConfigHandle().Save();
	}
}

+ (void)restoreGameFolderAccess
{
	for (NSData* bookmark in [NSUserDefaults.standardUserDefaults arrayForKey:@"gameFolderBookmarks"])
	{
		BOOL stale = NO;
		NSURL* url = [NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:nil];
		[url startAccessingSecurityScopedResource];
	}
}

+ (nullable NSString*)prepareTitle:(CemuTitle*)title
{
	CafeSystem::PREPARE_STATUS_CODE r = CafeSystem::PrepareForegroundTitle(title.titleId);
	switch (r)
	{
	case CafeSystem::PREPARE_STATUS_CODE::SUCCESS:
		return nil;
	case CafeSystem::PREPARE_STATUS_CODE::UNABLE_TO_MOUNT:
		return [NSString stringWithFormat:@"Unable to mount title.\nMake sure the game files are still present.\n\n%@", title.path];
	case CafeSystem::PREPARE_STATUS_CODE::INVALID_RPX:
		return @"The title's executable is invalid.";
	default:
		return @"Failed to launch game.";
	}
}

static void SetWindowSize(CGSize size, CGFloat scale)
{
	auto& windowInfo = WindowSystem::GetWindowInfo();
	windowInfo.width = (sint32)size.width;
	windowInfo.height = (sint32)size.height;
	windowInfo.phys_width = (sint32)(size.width * scale);
	windowInfo.phys_height = (sint32)(size.height * scale);
	windowInfo.dpi_scale = scale;
}

+ (nullable NSString*)launchPreparedTitleWithLayer:(CAMetalLayer*)layer pointSize:(CGSize)size scale:(CGFloat)scale
{
	auto& windowInfo = WindowSystem::GetWindowInfo();
	windowInfo.window_main.backend = WindowSystem::WindowHandleInfo::Backend::Cocoa;
	windowInfo.window_main.surface = (__bridge void*)layer;
	windowInfo.canvas_main = windowInfo.window_main;
	windowInfo.is_fullscreen = true;
	SetWindowSize(size, scale);

	try
	{
		g_renderer = std::make_unique<MetalRenderer>();
		MetalRenderer::GetInstance()->InitializeLayer({(sint32)size.width, (sint32)size.height}, true);
	}
	catch (const std::exception& ex)
	{
		cemuLog_log(LogType::Force, "Error when initializing Metal renderer: {}", ex.what());
		return [NSString stringWithFormat:@"Error when initializing Metal renderer:\n%s", ex.what()];
	}

	CafeSystem::LaunchForegroundTitle();
	return nil;
}

+ (void)updateLayerSize:(CGSize)size scale:(CGFloat)scale
{
	SetWindowSize(size, scale);
	if (auto* renderer = MetalRenderer::GetInstance())
		renderer->ResizeLayer({(sint32)size.width, (sint32)size.height}, true);
}

+ (BOOL)isTitleRunning
{
	return CafeSystem::IsTitleRunning();
}

+ (void)setAppActive:(BOOL)active
{
	WindowSystem::GetWindowInfo().app_active = active;
}

+ (void)setupDefaultControllerIfNeeded
{
	auto& inputManager = InputManager::instance();
	auto vpad = inputManager.get_vpad_controller(0);
	if (vpad && !vpad->get_controllers().empty())
		return;
#ifdef HAS_SDL
	auto provider = inputManager.get_api_provider(InputAPI::SDLController);
	if (!provider)
		return;
	auto controllers = provider->get_controllers();
	if (controllers.empty())
		return;
	auto emulated = inputManager.set_controller(0, EmulatedController::Type::VPAD, controllers.front());
	if (!emulated)
		return;
	emulated->set_default_mapping(controllers.front());
	inputManager.save(0);
	cemuLog_log(LogType::Force, "Assigned {} to the GamePad", controllers.front()->display_name());
#endif
}

+ (void)setTouchPosition:(CGPoint)position down:(BOOL)down
{
	auto& touch = InputManager::instance().m_main_touch;
	std::scoped_lock lock(touch.m_mutex);
	touch.position = {(sint32)position.x, (sint32)position.y};
	if (down && !touch.left_down)
		touch.left_down_toggle = true;
	touch.left_down = down;
}

+ (void)toggleGamePadScreen
{
	LatteGPUState.isDRCPrimary = !LatteGPUState.isDRCPrimary;
}

@end
