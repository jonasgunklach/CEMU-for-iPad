#import "EmulationViewController.h"
#import "CemuCore.h"

#import <GameController/GameController.h>
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
@property(nonatomic, strong) UIButton* menuButton;
@property(nonatomic, strong) GCVirtualController* virtualController;
@property(nonatomic) BOOL launched;
@property(nonatomic) BOOL wantsVirtualController;
@end

@implementation EmulationViewController

- (void)loadView
{
	self.metalView = [CemuMetalView new];
	self.metalView.backgroundColor = UIColor.blackColor;
	self.metalView.multipleTouchEnabled = NO;
	self.view = self.metalView;
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	self.menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[self.menuButton setImage:[UIImage systemImageNamed:@"ellipsis.circle"] forState:UIControlStateNormal];
	self.menuButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.5];
	self.menuButton.showsMenuAsPrimaryAction = YES;
	self.menuButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.menuButton];
	[NSLayoutConstraint activateConstraints:@[
		[self.menuButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
		[self.menuButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:8],
		[self.menuButton.widthAnchor constraintEqualToConstant:44],
		[self.menuButton.heightAnchor constraintEqualToConstant:44],
	]];
	[self rebuildMenu];

	// show the on-screen controller only while no physical controller is connected
	self.wantsVirtualController = GCController.controllers.count == 0;
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(controllersChanged) name:GCControllerDidConnectNotification object:nil];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(controllersChanged) name:GCControllerDidDisconnectNotification object:nil];
}

- (void)rebuildMenu
{
	__weak EmulationViewController* weakSelf = self;
	UIAction* swapScreens = [UIAction actionWithTitle:@"Swap TV / GamePad screen" image:[UIImage systemImageNamed:@"rectangle.2.swap"] identifier:nil handler:^(UIAction*) {
		[CemuCore toggleGamePadScreen];
	}];
	UIAction* virtualController = [UIAction actionWithTitle:@"On-screen controller" image:[UIImage systemImageNamed:@"gamecontroller"] identifier:nil handler:^(UIAction*) {
		weakSelf.wantsVirtualController = !weakSelf.wantsVirtualController;
		[weakSelf updateVirtualController];
		[weakSelf rebuildMenu];
	}];
	virtualController.state = self.wantsVirtualController ? UIMenuElementStateOn : UIMenuElementStateOff;
	UIAction* quit = [UIAction actionWithTitle:@"Quit Cemu" image:[UIImage systemImageNamed:@"power"] identifier:nil handler:^(UIAction*) {
		[weakSelf confirmQuit];
	}];
	quit.attributes = UIMenuElementAttributesDestructive;
	self.menuButton.menu = [UIMenu menuWithChildren:@[ swapScreens, virtualController, quit ]];
}

- (void)confirmQuit
{
	// Cemu does not support launching a second title in the same process yet
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Quit Cemu?" message:@"Unsaved progress will be lost." preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Quit" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
		exit(0);
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)controllersChanged
{
	BOOL hasPhysicalController = NO;
	for (GCController* controller in GCController.controllers)
	{
		if (!controller.isSnapshot && controller != self.virtualController.controller)
			hasPhysicalController = YES;
	}
	if (hasPhysicalController && self.wantsVirtualController)
	{
		self.wantsVirtualController = NO;
		[self updateVirtualController];
		[self rebuildMenu];
	}
	// SDL picks up the new device on its next event pump
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[CemuCore setupDefaultControllerIfNeeded];
	});
}

- (void)updateVirtualController
{
	if (self.wantsVirtualController && !self.virtualController)
	{
		GCVirtualControllerConfiguration* config = [GCVirtualControllerConfiguration new];
		config.elements = [NSSet setWithArray:@[
			GCInputLeftThumbstick, GCInputRightThumbstick,
			GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY,
			GCInputLeftShoulder, GCInputRightShoulder,
			GCInputLeftTrigger, GCInputRightTrigger,
			GCInputButtonMenu, GCInputButtonOptions,
		]];
		self.virtualController = [[GCVirtualController alloc] initWithConfiguration:config];
		[self.virtualController connectWithReplyHandler:nil];
	}
	else if (!self.wantsVirtualController && self.virtualController)
	{
		[self.virtualController disconnect];
		self.virtualController = nil;
	}
}

- (BOOL)prefersStatusBarHidden
{
	return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
	return YES;
}

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures
{
	return UIRectEdgeAll;
}

- (CGFloat)contentScale
{
	return self.view.window.windowScene.screen.nativeScale ?: 2.0;
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	CGFloat scale = self.contentScale;
	CAMetalLayer* layer = (CAMetalLayer*)self.metalView.layer;
	layer.contentsScale = scale;
	CGSize size = self.view.bounds.size;
	if (size.width == 0 || size.height == 0)
		return;

	if (!self.launched)
	{
		self.launched = YES;
		[CemuCore setupDefaultControllerIfNeeded];
		NSString* error = [CemuCore launchPreparedTitleWithLayer:layer pointSize:size scale:scale];
		if (error)
		{
			UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Error" message:error preferredStyle:UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
				exit(0);
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
	[self updateVirtualController];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	UIApplication.sharedApplication.idleTimerDisabled = NO;
	self.wantsVirtualController = NO;
	[self updateVirtualController];
}

#pragma mark - Touch input (GamePad touchscreen)

- (void)forwardTouch:(UITouch*)touch down:(BOOL)down
{
	CGPoint p = [touch locationInView:self.view];
	CGFloat scale = self.contentScale;
	[CemuCore setTouchPosition:CGPointMake(p.x * scale, p.y * scale) down:down];
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	[self forwardTouch:touches.anyObject down:YES];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	[self forwardTouch:touches.anyObject down:YES];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	[self forwardTouch:touches.anyObject down:NO];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	[self forwardTouch:touches.anyObject down:NO];
}

@end
