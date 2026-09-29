# iOS Simulator (Apple Silicon) build for the Cemu iOS port
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_SYSROOT iphonesimulator)
set(VCPKG_OSX_DEPLOYMENT_TARGET 17.0)
set(VCPKG_BUILD_TYPE release)

# The iOS 27 SDK declares pipe2() but it is unavailable on our lower deployment target
if(PORT STREQUAL "curl")
	list(APPEND VCPKG_CMAKE_CONFIGURE_OPTIONS -DHAVE_PIPE2=OFF)
endif()
