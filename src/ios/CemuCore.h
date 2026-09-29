#pragma once

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>

NS_ASSUME_NONNULL_BEGIN

// Objective-C facing wrapper around the emulator core, used by the UIKit frontend

@interface CemuTitle : NSObject
@property(nonatomic, copy) NSString* name;
@property(nonatomic, copy) NSString* path;
@property(nonatomic) uint64_t titleId;
@property(nonatomic) uint16_t version;
@end

@interface CemuCore : NSObject

// user-visible folder (Files app / Finder) holding keys.txt, mlc01, settings.xml, ...
@property(class, nonatomic, readonly) NSURL* documentsURL;
// Documents/games, scanned for titles
@property(class, nonatomic, readonly) NSURL* gamesURL;

// one-time initialization, runs the heavy parts on a background queue
+ (void)initializeWithCompletion:(void (^)(void))completion;
+ (BOOL)isInitialized;

+ (void)refreshTitlesWithCompletion:(void (^)(void))completion;
+ (NSArray<CemuTitle*>*)titles;

// adds a folder picked by the user (security-scoped URL) as a persistent game path
+ (void)addGameFolder:(NSURL*)url;

// mounts the title; returns an error message on failure
+ (nullable NSString*)prepareTitle:(CemuTitle*)title;
// creates the renderer on the given layer and starts emulation. Must be called on the main thread
+ (nullable NSString*)launchPreparedTitleWithLayer:(CAMetalLayer*)layer pointSize:(CGSize)size scale:(CGFloat)scale;
+ (void)updateLayerSize:(CGSize)size scale:(CGFloat)scale;
+ (BOOL)isTitleRunning;

// called by the frontend on scenePhase changes
+ (void)setAppActive:(BOOL)active;

// assigns the first connected game controller to the GamePad if nothing is configured yet
+ (void)setupDefaultControllerIfNeeded;
// touches on the main screen are forwarded as GamePad touchscreen input (position in pixels)
+ (void)setTouchPosition:(CGPoint)position down:(BOOL)down;
// swaps between TV and GamePad image on the main screen
+ (void)toggleGamePadScreen;

@end

NS_ASSUME_NONNULL_END
