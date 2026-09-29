#import "CemuAppDelegate.h"
#import "CemuCore.h"
#import "GameListViewController.h"

@implementation CemuAppDelegate

- (UISceneConfiguration*)application:(UIApplication*)application configurationForConnectingSceneSession:(UISceneSession*)session options:(UISceneConnectionOptions*)options
{
	UISceneConfiguration* config = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
	config.delegateClass = CemuSceneDelegate.class;
	return config;
}

@end

@implementation CemuSceneDelegate

- (void)scene:(UIScene*)scene willConnectToSession:(UISceneSession*)session options:(UISceneConnectionOptions*)connectionOptions
{
	self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene*)scene];
	GameListViewController* gameList = [GameListViewController new];
	self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:gameList];
	[self.window makeKeyAndVisible];
}

- (void)sceneDidBecomeActive:(UIScene*)scene
{
	[CemuCore setAppActive:YES];
}

- (void)sceneWillResignActive:(UIScene*)scene
{
	[CemuCore setAppActive:NO];
}

@end
