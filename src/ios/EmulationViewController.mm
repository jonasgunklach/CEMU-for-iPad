#import "EmulationViewController.h"
#import "CemuCore.h"

#import <QuartzCore/CAMetalLayer.h>

@interface CemuMetalView : UIView
@end

@implementation CemuMetalView

+ (Class)layerClass
{
	return CAMetalLayer.class;
}

@end

@interface EmulationViewController ()
@property(nonatomic, strong) CemuMetalView* metalView;
@property(nonatomic) BOOL launched;
@end

@implementation EmulationViewController

- (void)loadView
{
	self.metalView = [CemuMetalView new];
	self.metalView.backgroundColor = UIColor.blackColor;
	self.view = self.metalView;
}

- (BOOL)prefersStatusBarHidden
{
	return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
	return YES;
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	CGFloat scale = self.view.window.windowScene.screen.nativeScale ?: 2.0;
	CAMetalLayer* layer = (CAMetalLayer*)self.metalView.layer;
	layer.contentsScale = scale;
	CGSize size = self.view.bounds.size;
	if (size.width == 0 || size.height == 0)
		return;

	if (!self.launched)
	{
		self.launched = YES;
		NSString* error = [CemuCore launchPreparedTitleWithLayer:layer pointSize:size scale:scale];
		if (error)
		{
			UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Error" message:error preferredStyle:UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
				[self dismissViewControllerAnimated:YES completion:nil];
			}]];
			dispatch_async(dispatch_get_main_queue(), ^{
				[self presentViewController:alert animated:YES completion:nil];
			});
		}
		return;
	}
	[CemuCore updateLayerSize:size scale:scale];
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	UIApplication.sharedApplication.idleTimerDisabled = YES;
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	UIApplication.sharedApplication.idleTimerDisabled = NO;
}

@end
