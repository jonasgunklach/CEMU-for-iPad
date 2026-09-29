# iPadOS frontend (UIKit) - replaces the wxWidgets UI on iOS

set(CEMU_IOS_BUNDLE_ID "info.cemu.Cemu.ios" CACHE STRING "Bundle identifier of the iPadOS app")
set(CEMU_IOS_DEVELOPMENT_TEAM "" CACHE STRING "Apple development team ID used for code signing")

if (CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
	set(CEMU_IOS_PLATFORM_NAME "iPhoneSimulator")
else()
	set(CEMU_IOS_PLATFORM_NAME "iPhoneOS")
endif()
string(TOLOWER "${CEMU_IOS_PLATFORM_NAME}" CEMU_IOS_PLATFORM_NAME_LOWER)

add_executable(CemuiOS MACOSX_BUNDLE
	main.mm
	CemuAppDelegate.h
	CemuAppDelegate.mm
	CemuCore.h
	CemuCore.mm
	EmulationViewController.h
	EmulationViewController.mm
	GameListViewController.h
	GameListViewController.mm
	IOSWindowSystem.mm
	# shared with the desktop build: CemuCommonInit() etc.
	../main.cpp
	../mainLLE.cpp
)

cemu_use_precompiled_header(CemuiOS)
# the precompiled header is C++ only
set_source_files_properties(main.mm CemuAppDelegate.mm CemuCore.mm EmulationViewController.mm GameListViewController.mm IOSWindowSystem.mm
	PROPERTIES SKIP_PRECOMPILE_HEADERS ON COMPILE_OPTIONS "-fobjc-arc")

# game profiles and resources are the data path (see CemuCore.mm). They must not sit at the bundle root:
# a top level "resources" folder makes CFBundle treat the app as an old-style bundle without Info.plist
foreach(folder gameProfiles resources)
	add_custom_command(TARGET CemuiOS POST_BUILD
		COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_SOURCE_DIR}/bin/${folder}" "$<TARGET_BUNDLE_CONTENT_DIR:CemuiOS>/CemuData/${folder}")
endforeach()

set_target_properties(CemuiOS PROPERTIES
	OUTPUT_NAME "Cemu"
	MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
	MACOSX_BUNDLE_GUI_IDENTIFIER "${CEMU_IOS_BUNDLE_ID}"
	MACOSX_BUNDLE_EXECUTABLE_NAME "Cemu"
	MACOSX_BUNDLE_SHORT_VERSION_STRING "${EMULATOR_VERSION_MAJOR}.${EMULATOR_VERSION_MINOR}.${EMULATOR_VERSION_PATCH}"
	MACOSX_BUNDLE_BUNDLE_VERSION "${EMULATOR_VERSION_MAJOR}.${EMULATOR_VERSION_MINOR}.${EMULATOR_VERSION_PATCH}"
	XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${CEMU_IOS_BUNDLE_ID}"
	XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "2"
	XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/Cemu.entitlements"
	XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
	XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${CEMU_IOS_DEVELOPMENT_TEAM}"
)

if(ENABLE_SDL)
	target_link_libraries(CemuiOS PRIVATE SDL3::SDL3)
endif()

target_link_libraries(CemuiOS PRIVATE
	CemuAudio
	CemuCafe
	CemuCommon
	CemuComponents
	CemuConfig
	CemuGui
	CemuInput
	CemuResource
	CemuUtil
	"-framework UIKit"
	"-framework Metal"
	"-framework QuartzCore"
	"-framework UniformTypeIdentifiers"
	"-framework GameController"
	"-framework AVFoundation"
)
