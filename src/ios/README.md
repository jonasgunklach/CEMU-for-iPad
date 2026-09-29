# Cemu for iPadOS

Native UIKit frontend and Metal renderer for iPad. The wxWidgets UI, Vulkan, OpenGL, cubeb, libusb and
HIDAPI are disabled on iOS.

## Requirements

- Xcode 26 or newer (tested with Xcode 27 / iPadOS 27 SDK), CMake, Ninja, `pkgconf`, `autoconf`, `automake`, `libtool`
- An iPad with Apple silicon (M1 or newer recommended) on iPadOS 17+
- A **paid** Apple developer account. Cemu reserves a contiguous 4 GB range for the Wii U address space,
  which requires the `extended-virtual-addressing` and `increased-memory-limit` entitlements.
- [StikDebug](https://github.com/StikDebug/StikDebug) (or another debugger) for JIT, see below

## Building

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# 1. dependencies (arm64 device; use arm64-ios-simulator-cemu + a separate install root for the simulator)
./dependencies/vcpkg/bootstrap-vcpkg.sh -disableMetrics
./dependencies/vcpkg/vcpkg install --triplet arm64-ios-cemu \
    --overlay-triplets=dependencies/vcpkg_triplets --overlay-ports=dependencies/vcpkg_overlay_ports \
    --x-install-root=../vcpkg_installed_ios

# 2a. Xcode project (for signing and running on a device)
cmake -S . -B ../build-ios-xcode -G Xcode -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DVCPKG_INSTALLED_DIR=$PWD/../vcpkg_installed_ios -DVCPKG_MANIFEST_INSTALL=OFF \
    -DCEMU_IOS_DEVELOPMENT_TEAM=<your team id> -DCEMU_IOS_BUNDLE_ID=<your bundle id>
open ../build-ios-xcode/Cemu.xcodeproj   # scheme "CemuiOS", pick your iPad, Run

# 2b. or a quick Ninja build (unsigned, add -DCMAKE_OSX_SYSROOT=iphonesimulator for the simulator)
cmake -S . -B ../build-ios -G Ninja -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo -DVCPKG_INSTALLED_DIR=$PWD/../vcpkg_installed_ios -DVCPKG_MANIFEST_INSTALL=OFF
ninja -C ../build-ios CemuiOS
```

## Using it

Cemu's folder is visible in the Files app ("On My iPad › Cemu") and in Finder when the iPad is connected.

- `keys.txt` goes into the Cemu folder root
- games (`.wua`, `.wud`, `.wux`, `.rpx` or extracted folders) go into `games/`, or add any folder with the
  folder button in the game list
- `mlc01/`, `settings.xml`, `controllerProfiles/` and `log.txt` live there as well

Controllers (MFi, Xbox, PlayStation, Switch Pro, ...) are assigned to the GamePad automatically. Without a
controller an on-screen controller is shown. Touches on the screen are sent to the GamePad touchscreen. The
`...` button in the top left corner swaps between the TV and the GamePad image.

## JIT

iPadOS does not let apps create executable memory, so without help Cemu can only use its interpreter, which
is far too slow for games. With a debugger attached Cemu maps a 512 MB code pool twice (writable + executable
alias, see `util/MemMapper/JitMemory_iOS.cpp`). On iPadOS 26+ devices with TXM the debugger must additionally
prepare the pool. Cemu requests that using the `brk #0xf00d` protocol of StikDebug's universal JIT script.

1. Install StikDebug and pair it with the iPad
2. Launch Cemu, tap the bolt button in the game list and choose "Open StikDebug" (or enable JIT for Cemu from
   inside StikDebug)
3. Switch back to Cemu. The bolt turns green once JIT is active. It has to be done again after every launch.

If enabling JIT crashes Cemu (for example because the debugger did not run the script on a TXM device), Cemu
skips JIT on the next launch and falls back to the interpreter.

## Status / known limitations

- Launching a second game requires restarting the app
- No settings UI yet (edit `settings.xml`, graphic packs work through `graphicPacks/`)
- GamePad as a second screen (split view / external display) is not implemented yet
- No hotkeys, no motion controls, no Wiimote support
