#import "GameListViewController.h"
#import "CemuCore.h"
#import "EmulationViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface GameListViewController () <UIDocumentPickerDelegate>
@property(nonatomic, copy) NSArray<CemuTitle*>* titles;
@property(nonatomic, strong) UIActivityIndicatorView* spinner;
@end

@implementation GameListViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.title = @"Cemu";
	self.titles = @[];
	[self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"title"];

	self.navigationItem.rightBarButtonItems = @[
		[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder.badge.plus"] style:UIBarButtonItemStylePlain target:self action:@selector(addFolder)],
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)],
	];

	self.refreshControl = [UIRefreshControl new];
	[self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
	self.tableView.backgroundView = self.spinner;
	[self.spinner startAnimating];

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadTitles) name:@"CemuRefreshGameList" object:nil];

	[CemuCore initializeWithCompletion:^{
		[self.spinner stopAnimating];
		[self reloadTitles];
	}];
}

- (void)reloadTitles
{
	if (!CemuCore.isInitialized)
		return;
	self.titles = CemuCore.titles;
	[self.tableView reloadData];
	[self.refreshControl endRefreshing];
	[self updateEmptyState];
}

- (void)updateEmptyState
{
	if (self.titles.count > 0)
	{
		self.tableView.backgroundView = nil;
		return;
	}
	UILabel* label = [UILabel new];
	label.numberOfLines = 0;
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = UIColor.secondaryLabelColor;
	label.text = @"No games found.\n\nCopy your dumped games (.wua, .wud, .wux or extracted folders) and keys.txt into the Cemu folder using the Files app or Finder, or add a folder with the button above.";
	UIView* container = [UIView new];
	label.translatesAutoresizingMaskIntoConstraints = NO;
	[container addSubview:label];
	[NSLayoutConstraint activateConstraints:@[
		[label.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
		[label.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
		[label.widthAnchor constraintLessThanOrEqualToConstant:520],
		[label.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.layoutMarginsGuide.leadingAnchor],
	]];
	self.tableView.backgroundView = container;
}

- (void)refresh
{
	if (!CemuCore.isInitialized)
		return;
	[CemuCore refreshTitlesWithCompletion:^{
		[self reloadTitles];
	}];
}

- (void)addFolder
{
	UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeFolder ]];
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
	for (NSURL* url in urls)
		[CemuCore addGameFolder:url];
	[self refresh];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
	return self.titles.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
	UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"title" forIndexPath:indexPath];
	CemuTitle* title = self.titles[indexPath.row];
	UIListContentConfiguration* content = [UIListContentConfiguration subtitleCellConfiguration];
	content.text = title.name;
	content.secondaryText = [NSString stringWithFormat:@"%016llx  v%u", title.titleId, title.version];
	cell.contentConfiguration = content;
	return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (CemuCore.isTitleRunning)
	{
		[self showError:@"A game is already running. Restart Cemu to launch another game."];
		return;
	}
	CemuTitle* title = self.titles[indexPath.row];
	NSString* error = [CemuCore prepareTitle:title];
	if (error)
	{
		[self showError:error];
		return;
	}
	EmulationViewController* emulation = [EmulationViewController new];
	emulation.modalPresentationStyle = UIModalPresentationFullScreen;
	[self presentViewController:emulation animated:YES completion:nil];
}

- (void)showError:(NSString*)message
{
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Error" message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
