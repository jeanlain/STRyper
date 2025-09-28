//
//  MainWindowController.m
//  STRyper
//
//  Created by Jean Peccoud on 11/03/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.



#import "MainWindowController.h"
#import "NSSplitViewController+SplitViewControllerAdditions.h"
#import "SampleTableController.h"
#import "GenotypeTableController.h"
#import "SampleInspectorController.h"
#import "FolderListController.h"
#import "PanelListController.h"
#import "SizeStandardTableController.h"
#import "SampleSearchHelper.h"
#import "DetailedViewController.h"


@interface MainWindowController ()

/// Property bound to the active tab number of the tabView
@property (nonatomic) NSInteger activeBottomTab;

@end


@implementation MainWindowController {
	/// Outlet used to populate the tab view by adding tabs, which are loaded from other nibs.
	/// We could reach the desired view in code by enumerating subviews, but it seems safer this way
	__weak IBOutlet NSTabView *tabView;
	
	/// backs the ``errorLogWindow`` property.
	IBOutlet NSPanel *_errorLogWindow;
}


typedef NS_ENUM(NSUInteger, bottomTab) {		/// the number of the tab in the bottom tab view
	sampleInspectorTab,
	genotypeTab,
	markerTab,
	sizeStandardTab
} ;


@synthesize mainSplitViewController = _mainSplitViewController,
verticalSplitViewController = _verticalSplitViewController;


+ (instancetype)sharedController {
	static MainWindowController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = self.new;
	});
	return controller;
}


- (NSNibName)windowNibName {
	return @"MainWindow";
}


- (void)windowDidLoad {
	[super windowDidLoad];
	NSWindow *window = self.window;
	window.tabbingMode = NSWindowTabbingModeDisallowed;
	if (@available(macOS 11.0, *)) {
		window.styleMask |= NSWindowStyleMaskFullSizeContentView;
		window.toolbarStyle = NSWindowToolbarStyleUnified;
		window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleAutomatic;
	} else {
		window.titleVisibility = NSWindowTitleVisible;
	}
	
	[window orderFront:self];
	[window makeMainWindow];
	window.acceptsMouseMovedEvents = NO;
	
	
	if(!self.mainSplitViewController) {
		NSLog(@"failed to load the main split view.");
		abort();
	}
	
		
	///Adding the sample inspector to the tab view.
	SampleInspectorController *sampleInspectorController = SampleInspectorController.sharedController;
	if(sampleInspectorController.view) {
		[tabView addTabViewItem:[NSTabViewItem tabViewItemWithViewController:sampleInspectorController]];
	} else {
		NSLog(@"failed to load the sample table.");
		abort();
	}
		
	///Adding the genotype tab.
	GenotypeTableController *genotypeTableController = GenotypeTableController.sharedController;
	if(genotypeTableController.view) {
		[tabView addTabViewItem:[NSTabViewItem tabViewItemWithViewController:genotypeTableController]];
	} else {
		NSLog(@"failed to load the genotype table.");
		abort();
	}
	
	
	///Adding the panel + marker tab.
	PanelListController *panelListController = PanelListController.sharedController;
	if(panelListController.view) {
		[tabView addTabViewItem:[NSTabViewItem tabViewItemWithViewController:panelListController]];
	} else {
		NSLog(@"failed to load the panel list.");
		abort();
	}
	
	
	///Adding the size standard tab.
	SizeStandardTableController *sizeStandardTableController = SizeStandardTableController.sharedController;
	if(sizeStandardTableController.view) {
		[tabView addTabViewItem:[NSTabViewItem tabViewItemWithViewController:sizeStandardTableController]];
	} else {
		NSLog(@"failed to load the size standard table.");
		abort();
	}
	
	/// To remember which tab is shown and to synchronize the NSSegmentedControl button activating tab and the tabView, we use a property set in user defaults.
	[tabView bind:NSSelectedIndexBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:BottomTab options:nil];
    _activeBottomTab = -1; /// To force calling the setter in the binding below.
    [self bind:@"activeBottomTab" toObject:NSUserDefaults.standardUserDefaults withKeyPath:BottomTab options:nil];

	
	if(!SampleSearchHelper.sharedHelper) {
		/// we init the search controller as must perform the search in case there are smart folder in the database
		NSLog(@"failed to load the search helper.");
		/// but we don't abort if it is absent.
	}
	
	tabView.delegate = self;
	
	NSToolbar *toolbar = window.toolbar;
	if(!toolbar) {
		toolbar = [[NSToolbar alloc] initWithIdentifier:mainToolbarID];
		toolbar.allowsUserCustomization = YES;
		toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
		toolbar.delegate = self;
		toolbar.autosavesConfiguration = YES;
		window.toolbar = toolbar;
	}
	
	[self restoreSelection];
}


- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	/// Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
	return AppDelegate.sharedInstance.managedObjectContext.undoManager;
}
	


- (NSSplitViewController *)mainSplitViewController {
	if(!_mainSplitViewController) {
		/// the main split view is in our window in the nib
		NSSplitView *mainSplitView = self.window.contentView.subviews.firstObject;
		if(mainSplitView.subviews.count < 3) {
			return nil;
		}
		_mainSplitViewController = NSSplitViewController.new;
		_mainSplitViewController.splitView = mainSplitView;
		_mainSplitViewController.view = mainSplitView;
		
		/// we load the left pane (side bar)
		if(FolderListController.sharedController.view) {
			[_mainSplitViewController addSplitViewItem:[NSSplitViewItem sidebarWithViewController:FolderListController.sharedController]];
			_mainSplitViewController.splitViewItems.firstObject.minimumThickness = 150;
		} else {
			return nil;
		}
		/// the middle pane, which is itself a vertical split view
		if(self.verticalSplitViewController.view) {
			NSSplitViewItem *item = [NSSplitViewItem contentListWithViewController:self.verticalSplitViewController];
			item.minimumThickness = 350.0;
			item.canCollapse = NO;
			[_mainSplitViewController addSplitViewItem:item];
		} else {
			return nil;
		}
		
		/// the right pane containing the outline view showing traces and/or markers
		DetailedViewController *detailedViewController = DetailedViewController.sharedController;
		NSView *view = detailedViewController.view;
		if(view) {
			NSSplitViewItem *item = [NSSplitViewItem splitViewItemWithViewController:detailedViewController];
			item.canCollapse = YES;
			/// we determine its minimum width based on the button shown at the bottom (which should not be clipped)
			NSView *button = [view viewWithTag:-5];
			CGFloat thickness = 420;
			if(button) {
				thickness = NSMaxX(button.frame) + 5;
			}
			item.minimumThickness = thickness;
			item.collapseBehavior = NSSplitViewItemCollapseBehaviorPreferResizingSiblingsWithFixedSplitView;	
			/// the above doesn't appear to work consistently as revealing the bottom pane may sometimes increase the window height while there is still space
			[_mainSplitViewController addSplitViewItem:item];
		} else {
			return nil;
		}
		
		mainSplitView.autosaveName = [mainSplitView.identifier stringByAppendingString:@"Configuration"];

	}
	return _mainSplitViewController;
}


- (NSSplitViewController *)verticalSplitViewController {
	if(!_verticalSplitViewController) {
		
		NSView *bottomPane = tabView.superview;		/// the bottom pane of the controller's split view (which contains the tab view)
		/// we record a reference to it, as adding its superview to the controller will clear it from the superview
		
		NSSplitView *midPane = (NSSplitView *)bottomPane.superview;	/// the controller's split view itself
		if(!bottomPane || ![midPane isKindOfClass:NSSplitView.class]) {
			return nil;
		}
	
		_verticalSplitViewController = NSSplitViewController.new;
		_verticalSplitViewController.splitView = midPane;
		_verticalSplitViewController.view = midPane;
		
		/// we add the top pane
		SampleTableController *sampleTableController = SampleTableController.sharedController;
		if(sampleTableController.view) {
			NSSplitViewItem *item = [NSSplitViewItem contentListWithViewController:sampleTableController];
			item.minimumThickness = 30.0;
			item.canCollapse = NO;
			[_verticalSplitViewController addSplitViewItem:item];
		} else {
			return nil;
		}
		
		/// the bottom pane (containing the tab view) doesn't have a controller. We create one.
		NSViewController *controller = NSViewController.new;
		controller.view = bottomPane;
		NSSplitViewItem *item =  [NSSplitViewItem splitViewItemWithViewController:controller];
		item.canCollapse = YES;
		item.minimumThickness = 150.0;
		[_verticalSplitViewController addSplitViewItem:item];
		
		midPane.autosaveName = [midPane.identifier stringByAppendingString:@"Configuration"];
	}
	return _verticalSplitViewController;
}



static const NSToolbarIdentifier mainToolbarID = @"mainToolbarID";
static const NSToolbarItemIdentifier undoRedoGroup = @"undoRedoGroup",
	leftPaneButtonID = @"leftPaneButtonID",
	undoButtonID = @"undoButtonID",
	redoButtonID = @"redoButtonID",
	importSamplesButtonID = @"importSamplesButtonID",
	importFolderButtonID = @"importFolderButtonID",
	importPanelButtonID = @"importPanelButtonID",
	newFolderButtonID = @"newFolderButtonID",
	deleteSelectionButtonID = @"deleteSelectionButtonID",
	exportButtonID = @"exportButtonID",
	sampleSearchButtonID = @"sampleSearchButtonID",
	rightPaneButtonID = @"rightPaneButtonID";


- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
	if([itemIdentifier isEqualToString: undoRedoGroup]) {
		NSToolbarItemGroup *undoRedo = [[NSToolbarItemGroup alloc] initWithItemIdentifier:itemIdentifier];
		NSToolbarItem *undoButton = [[NSToolbarItem alloc] initWithItemIdentifier:undoButtonID];
		NSToolbarItem *redoButton = [[NSToolbarItem alloc] initWithItemIdentifier:redoButtonID];
		undoButton.image = [NSImage imageNamed:ACImageNameUndo];
		undoButton.label = @"Undo";
		undoButton.paletteLabel = undoButton.label;
		undoButton.action = @selector(undo:);
		undoButton.target = self;
		redoButton.image = [NSImage imageNamed:ACImageNameRedo];
		redoButton.label = @"Redo";
		redoButton.paletteLabel = redoButton.label;
		redoButton.action = @selector(redo:);
		redoButton.target = self;
		undoRedo.subitems = @[undoButton, redoButton];
		if (@available(macOS 10.15, *)) {
			undoRedo.bordered = YES;
			undoRedo.selectionMode = NSToolbarItemGroupSelectionModeMomentary;
		}
		return undoRedo;
	}
	
	NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
	if (@available(macOS 10.15, *)) {
		item.bordered = YES;
	}
	item.target = self;
	
	if([itemIdentifier isEqualToString:leftPaneButtonID]) {
		item.image = [NSImage imageNamed:ACImageNameSideBar];
		item.label = @"Sidebar";
		item.tag = 0;
		item.action = @selector(toggleSidebar:);
	} else if([itemIdentifier isEqualToString:newFolderButtonID]) {
		item.image = [NSImage imageNamed:ACImageNameNewFolder];
		item.label = @"New folder";
		item.toolTip = @"New folder";
		item.action = @selector(addSampleOrSmartFolder:);
	} else if([itemIdentifier isEqualToString:importSamplesButtonID]) {
		item.image = [NSImage imageNamed:ACImageNameImportSamples];
		item.label = @"Import samples";
		item.toolTip = @"Import chromatogram files";
		item.action = @selector(importSamples:);
	} else if([itemIdentifier isEqualToString:importFolderButtonID]) {
		item.image = [NSImage imageNamed:ACImageNameImportFolder];
		item.label = @"Import archive";
		item.toolTip = @"Import archived folder";
		item.action = @selector(importFolder:);
	} else if([itemIdentifier isEqualToString:importPanelButtonID]) {
		item.image = [NSImage imageNamed:ACImageNameImportPanel];
		item.label = @"Import markers";
		item.toolTip = @"Import panel(s) of markers";
		item.action = @selector(importPanels:);
	} else if([itemIdentifier isEqualToString:sampleSearchButtonID]) {
		item.image = [NSImage imageNamed:ACImageNameLoupe];
		item.label = @"Sample search";
		item.toolTip = @"New sample search";
		item.tag = 4;
		item.action = @selector(addSampleOrSmartFolder:);
	} else if([itemIdentifier isEqualToString:rightPaneButtonID]) {
		item.image = [NSImage imageNamed:ACImageNameRightsideBar];
		item.label = @"Detailed view";
		item.tag = 2;
		item.action = @selector(toggleRightPane:);
	} else if([itemIdentifier isEqualToString:deleteSelectionButtonID]) {
		item.image = [NSImage imageNamed:ACImageNameLargeTrash];
		item.label = @"Delete";
		item.target = nil;
		item.action = @selector(remove:);
	} else if([itemIdentifier isEqualToString:exportButtonID]) {
		item.image = [NSImage imageNamed:ACImageNameExportLarge];
		item.label = @"Export";
		item.target = nil;
		item.action = @selector(exportSelection:);
	}
	item.paletteLabel = item.label;
	return item;
}


- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
	NSMutableArray *items = @[leftPaneButtonID, undoRedoGroup, NSToolbarSpaceItemIdentifier, newFolderButtonID,
			 importSamplesButtonID, importFolderButtonID, importPanelButtonID, NSToolbarSpaceItemIdentifier,
			 exportButtonID, deleteSelectionButtonID, sampleSearchButtonID,
			 NSToolbarFlexibleSpaceItemIdentifier, rightPaneButtonID].mutableCopy ;
	
	if (@available(macOS 11.0, *)) {
		[items insertObject:NSToolbarSidebarTrackingSeparatorItemIdentifier atIndex:1];
	}
	return items.copy;
}

- (BOOL)toolbar:(NSToolbar *)toolbar itemIdentifier:(NSToolbarItemIdentifier)itemIdentifier canBeInsertedAtIndex:(NSInteger)index {
	if(index <= 1 && ![itemIdentifier isEqualToString:leftPaneButtonID]) {
		return NO;
	}
	return YES;
}


- (NSSet<NSToolbarItemIdentifier> *)toolbarImmovableItemIdentifiers:(NSToolbar *)toolbar {
	if (@available(macOS 11.0, *)) {
		return [NSSet setWithObjects: leftPaneButtonID, NSToolbarSidebarTrackingSeparatorItemIdentifier, nil];
	}
	return NSSet.new;
}


- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
	return [self toolbarDefaultItemIdentifiers:toolbar];
}


- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	/// We make the selected tab the first responder so that menu and toolbar items have appropriate actions.
	/// For instance, when the user selects the genotype tab, the export button should export genotypes.
	NSView *view = tabViewItem.view;
	NSWindow *window = view.window;
	if(window && tabViewItem.viewController) {
		NSView *firstResponder = (NSView*)window.firstResponder;
		if([firstResponder respondsToSelector:@selector(isDescendantOf:)] && ![firstResponder isDescendantOf:view]) {
			[window makeFirstResponder:tabViewItem.viewController];
		}
	}
}


- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	return YES;
}


# pragma mark - setting the contents of the detailed outline view

UserDefaultKey SourceControllerKey = @"sourceControllerKey";
static NSString *GenotypeTableControllerKey = @"GenotypeTableControllerKey";
static NSString *SampleTableControllerKey = @"SampleTableControllerKey";
static NSString *MarkerTableControllerKey = @"MarkerTableControllerKey";
static NSString *NoSourceControllerKey = @"NoSourceControllerKey";


- (void)setSourceController:(TableViewController *)controller {
	/// this message in sent by a TableViewController when its table is clicked (and in other circumstances), so that its selected items show in the detailed outline view
	if(controller.tableView == nil || controller.tableContent == nil) {
		return;
	}
	
	if(controller == GenotypeTableController.sharedController) {
		/// if we 	activate the genotype table, we make sure its tab is visible
		/// we do it even if it was already the active table, as it could have been masked since then
		[self activateTabNumber: genotypeTab];
	}
	if(controller != self.sourceController) {
		_sourceController = controller;
		
		NSTableView *activeTableView = controller.tableView;
		if(activeTableView.window.firstResponder != activeTableView) {
			[activeTableView.window makeFirstResponder:activeTableView];
		}
	}
}


-(void)recordSourceController {
	TableViewController *sourceController = self.sourceController;
	NSUserDefaults *standardUserDefaults = NSUserDefaults.standardUserDefaults;
	
	if(sourceController == GenotypeTableController.sharedController) {
		[standardUserDefaults setObject:GenotypeTableControllerKey forKey:SourceControllerKey];
	} else if(sourceController == SampleTableController.sharedController) {
		[standardUserDefaults setObject:SampleTableControllerKey forKey:SourceControllerKey];
	} else if(sourceController == MarkerTableController.sharedController) {
		[standardUserDefaults setObject:MarkerTableControllerKey forKey:SourceControllerKey];
	} else {
		[standardUserDefaults setObject:NoSourceControllerKey forKey:SourceControllerKey];
	}
}


-(void) restoreSelection {
	[SampleTableController.sharedController restoreSelectedItems];
	[GenotypeTableController.sharedController restoreSelectedItems];
	NSString *key = [NSUserDefaults.standardUserDefaults stringForKey:SourceControllerKey];
	if([key isEqualToString:GenotypeTableControllerKey]) {
		self.sourceController = GenotypeTableController.sharedController;
	} else if([key isEqualToString:SampleTableControllerKey]) {
		self.sourceController = SampleTableController.sharedController;
	} else if([key isEqualToString:MarkerTableControllerKey]) {
		self.sourceController = MarkerTableController.sharedController;
	}
}


# pragma mark -
# pragma mark UI validation and action messages


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {

	if(menuItem.action == @selector(deleteSelection:) || menuItem.action == @selector(rename:) || menuItem.action == @selector(remove:)) {
		/// If such message reaches us, it means that no responder could handle it.
		/// Because its title depends on the context, it is better to hide the item rather than show a disabled "Delete Sample" item, for instance.
		menuItem.hidden = YES;
		return NO;
	}
	
	if(menuItem.action == @selector(importSamples:)) {
		return FolderListController.sharedController.canImportSamples;
	}
	
	if(menuItem.action == @selector(editSmartFolder:)) {
		return [FolderListController.sharedController validateMenuItem:menuItem];
	}
	
	if(menuItem.action == @selector(toggleSidebar:)) {
		menuItem.title = [self.mainSplitViewController.splitViewItems.firstObject isCollapsed]? @"Show Folder List" : @"Hide Folder List";
		return YES;
	}
	
	if(menuItem.action == @selector(toggleRightPane:)) {
		menuItem.title = [self.mainSplitViewController.splitViewItems.lastObject isCollapsed]? @"Show Right Pane" : @"Hide Right Pane";
		return YES;
	}
	
	if(menuItem.action == @selector(toggleBottomPane:)) {
		menuItem.title = [self.verticalSplitViewController.splitViewItems.lastObject isCollapsed]? @"Show Bottom Pane" : @"Hide Bottom Pane";
		return YES;
	}
	
	if(menuItem.action == @selector(moveSelectionByStep:)) {
		return [self.sourceController validateMenuItem:menuItem];
	}
	
	if(menuItem.action == @selector(activateTab:)) {
		/// we show the tick-mark if the menu corresponds to the tab that is active and if the bottom pane is not collapsed.
		/// The tag of the menu refers to the index of the tab
		BOOL collapsed = self.verticalSplitViewController.splitViewItems.lastObject.isCollapsed;
		menuItem.state = menuItem.tag == [tabView.tabViewItems indexOfObject: tabView.selectedTabViewItem] && !collapsed? NSControlStateValueOn : NSControlStateValueOff;
		return YES;
	}
	
	if(menuItem.action == @selector(showErrorLogWindow:)) {
		menuItem.state = self.errorLogWindow.isVisible? NSControlStateValueOn : NSControlStateValueOff;
		return YES;
	}
	
	if(menuItem.action == @selector(topFluoMode:)) {
		if(DetailedViewController.sharedController.showMarkers) {
			return NO;
		}
		/// Menu items that call this has a tag corresponding to the TraceTopFluoMode of the use default.
		/// We add a check mark to the menu item it it corresponds to the current mode
		TopFluoMode fluoMode = [NSUserDefaults.standardUserDefaults integerForKey:TraceTopFluoMode];
		menuItem.state = menuItem.tag == fluoMode? NSControlStateValueOn : NSControlStateValueOff;
		return YES;
	}
	
	if(menuItem.action == @selector(stackMode:)) {
		NSInteger tag = menuItem.tag;
		DetailedViewController *controller = DetailedViewController.sharedController;
		if(tag == -1) { /// The item that contains the submenu to stack traces.
						/// We only enable it when the detailed view shows samples.
			return !controller.showMarkers && !controller.showGenotypes;
		}
		
		if(tag == 3) { /// The menu item to stack genotypes per marker
			[menuItem bind:NSEnabledBinding toObject:controller withKeyPath:@"showGenotypes" options:nil];
			[menuItem bind:NSValueBinding toObject:controller withKeyPath:@"stackGenotypes" options:nil];
			return controller.showGenotypes;
		}
		
		/// Menu items that call this have a tag corresponding to the TraceStackMode of the use default.
		/// We add a check mark to the menu item it it corresponds to the current mode
		StackMode stackMode = [NSUserDefaults.standardUserDefaults integerForKey:TraceStackMode];
		menuItem.state = tag == stackMode? NSControlStateValueOn : NSControlStateValueOff;
		return YES;
	}
	
	if(menuItem.action == @selector(exportSelection:)) {
		TableViewController *exporter = self.relevantExporter;
		if(exporter.canExportItems) {
			return [exporter validateMenuItem:menuItem];
		} else {
			return NO;
		}
	}
	
	if(menuItem.action == @selector(printTraces:)) {
		return DetailedViewController.sharedController.tableView.numberOfRows > 0;
	}
	
	return YES;
}


- (void)deleteSelection:(id)sender {
	/// We implement this only to be sent the validateMenuItem message to hide the item
}


- (void)exportSelection:(id)sender {
	[self.relevantExporter exportSelection:sender];
}


- (void)rename:(id)sender {
	/// We implement this only to be sent the validateMenuItem message to hide the item
}


- (void)remove:(id)sender {
	/// We implement this only to be sent the validateMenuItem message to hide the item
}


-(IBAction)topFluoMode:(id)sender {
	if([sender respondsToSelector:@selector(tag)]) {
		NSInteger tag = [sender tag];
		if(tag >= 0 && tag <= 2) {
			[NSUserDefaults.standardUserDefaults setInteger:tag forKey:TraceTopFluoMode];
		}
	}
}


-(IBAction)stackMode:(id)sender {
	if([sender respondsToSelector:@selector(tag)]) {
		NSInteger tag = [sender tag];
		if(tag >= 0 && tag <= 2) {
			[NSUserDefaults.standardUserDefaults setInteger:tag forKey:TraceStackMode];
		}
	}
}


- (void)addSampleOrSmartFolder:(id)sender {
	[FolderListController.sharedController addFolder:sender];
}


- (void)moveSelectionByStep:(id)sender {
	[self.sourceController moveSelectionByStep:sender];
}


-(void)importSamples:(id)sender {
	[SampleTableController.sharedController importSamples:sender];
}


-(void)toggleSidebar:(id)sender {
	[self.mainSplitViewController togglePane:sender];
}


-(void)toggleRightPane:(id)sender {
	[self.mainSplitViewController togglePane:sender];
}


-(void)toggleBottomPane:(id)sender {
	BOOL collapsed = self.verticalSplitViewController.splitViewItems.lastObject.isCollapsed;
	[self.verticalSplitViewController togglePane:sender];
	if([sender respondsToSelector:@selector(setToolTip:)]) {
		[sender setToolTip: collapsed? @"Collapse bottom pane" : @"Expand bottom pane"];
	}
}


- (void)editSmartFolder:(id)sender {
	[FolderListController.sharedController editSmartFolder:sender];
}


-(void) importFolder:(id)sender {
	[FolderListController.sharedController importFolder:sender];
}


- (void)importPanels:(id)sender {
	[PanelListController.sharedController importPanels:sender];
}


-(void) activateTab:(id)sender {
	if([sender respondsToSelector:@selector(tag)]) {
		[self activateTabNumber:[sender tag]];
	}
}


- (void)activateTabNumber:(NSInteger)number {
	if(number >= 0 && number <= tabView.tabViewItems.count) {
		[NSUserDefaults.standardUserDefaults setInteger:number forKey:BottomTab];		/// this activates the corresponding tab, as the tabview's selected index is bound to the user defaults key.
		NSSplitViewItem *item = self.verticalSplitViewController.splitViewItems.lastObject;
		if(item.collapsed) {
			[self.verticalSplitViewController togglePaneNumber:1];
		}
	}
}


- (void)setActiveBottomTab:(NSInteger)activeBottomTab {
	/// We determine if the sample inspector is shown. If not, there is not need to update it (via a binding)
	
	_activeBottomTab = activeBottomTab;
	SampleInspectorController *sampleInspectorController = SampleInspectorController.sharedController;
	if(activeBottomTab == sampleInspectorTab) {
		[sampleInspectorController bind:@"samples" toObject:SampleTableController.sharedController.tableContent withKeyPath:NSSelectedObjectsBinding options:nil];
	} else {
		[sampleInspectorController unbind:@"samples"];
		sampleInspectorController.samples = nil;
	}
}



- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
	NSString *toolTip;
	if(item.action == @selector(toggleSidebar:)) {
		toolTip = [self.mainSplitViewController.splitViewItems.firstObject isCollapsed]? @"Show folder list" : @"Hide folder list";
	} else if(item.action == @selector(toggleRightPane:)) {
		toolTip = [self.mainSplitViewController.splitViewItems.lastObject isCollapsed]? @"Show detailed view" : @"Hide detailed view";
	} else if(item.action == @selector(undo:)) {
		toolTip = self.window.firstResponder.undoManager.undoMenuItemTitle;
	} else if(item.action == @selector(redo:)) {
		toolTip = self.window.firstResponder.undoManager.redoMenuItemTitle;
	} else if(item.action == @selector(exportSelection:)) {
		TableViewController *exporter =  self.relevantExporter;
		if(exporter.canExportItems) {
			return [exporter validateToolbarItem:item];
		} else {
			return NO;
		}
	}
	if(toolTip && ![item.toolTip isEqualToString:toolTip]) {
		item.toolTip = toolTip;
	}
	
	if(item.action == @selector(undo:)) {
		return self.window.firstResponder.undoManager.canUndo;
	}
	if(item.action == @selector(redo:)) {
		return self.window.firstResponder.undoManager.canRedo;
	}
	return YES;
}


/// The object that could handle an `exportSelection:` message that has not be handled in the responder chain.
-(TableViewController *)relevantExporter {
	/// If the detailed view is active, it is intuitive to export something related to what it shows (markers, samples, genotypes).
	NSView *firstResponder = (NSView *)self.window.firstResponder;
	if([firstResponder respondsToSelector:@selector(isDescendantOf:)]) {
		if([firstResponder isDescendantOf:DetailedViewController.sharedController.view]) {
			/// The detailed view is active. In this case, what to export pertains to the source controller.
			TableViewController *sourceController = self.sourceController;
			if([sourceController isKindOfClass:MarkerTableController.class]) {
				return PanelListController.sharedController;
			}
			if(sourceController == SampleTableController.sharedController) {
				/// If the detailed view shows samples, it makes sense to be able to export the selected folder.
				return FolderListController.sharedController;
			}
			return sourceController;
		}
		if([firstResponder isDescendantOf:PanelListController.sharedController.view]) {
			return PanelListController.sharedController;
		}
	}
	/// Otherwise, it may make sense to allow exporting the selected folder, at its content is always visible.
	return FolderListController.sharedController;
}


-(IBAction)undo:(id)sender {
	if(![self.window tryToPerform:@selector(undo:) with:sender]) {
		/// The condition above should avoid calling undo ourselves on the undo manager, but we do it anyway.
		[self.window.firstResponder.undoManager undo];
	}
}


-(IBAction)redo:(id)sender {
	if(![self.window tryToPerform:@selector(redo:) with:sender]) {
		[self.window.firstResponder.undoManager redo];
	}
}


-(IBAction)printTraces:(id)sender {
    [DetailedViewController.sharedController print:sender];
}


# pragma mark - managing the error log window

- (void)setLogWindowText:(NSString *)log {
	NSWindow *errorLogWindow = self.errorLogWindow;
	NSScrollView *scrollview = errorLogWindow.contentView.subviews.firstObject;
	NSTextView *textView = scrollview.documentView;
	if([textView respondsToSelector:@selector(setString:)]) {
		textView.string = log;
	}
}


- (void)showErrorLogWindow:(id)sender {
	[self.errorLogWindow makeKeyAndOrderFront:self];
}


- (NSWindow *)errorLogWindow {
	if(!_errorLogWindow) {
		[NSBundle.mainBundle loadNibNamed:@"ErrorLogWindow" owner:self topLevelObjects:nil];
	}
	return _errorLogWindow;
}



-(NSString *)populateErrorLogWithError:(NSError *)error {
	if(!error) {
		return nil;
	}
	
	NSArray *errors = error.userInfo[NSDetailedErrorsKey];
	if(errors.count == 0) {
		errors = @[error];
	}
	NSMutableArray *strings = NSMutableArray.new;
	
	for(NSError *error in errors) {
		NSString *description = error.userInfo[NSLocalizedDescriptionKey];
		NSString *reason = error.userInfo[NSLocalizedFailureReasonErrorKey];
		NSString *suggestion = error.userInfo[NSLocalizedRecoverySuggestionErrorKey];
		NSString *string;
		if(reason.length > 0 && description.length > 0) {
			if(![reason isEqualToString:description]) {
				if(reason.length > description.length && [reason rangeOfString:description].location != NSNotFound) {
					string = reason;
				} else if(reason.length < description.length && [description rangeOfString:reason].location != NSNotFound) {
					string = description;
				} else {
					string = [description stringByAppendingFormat:@" %@", reason];
				}
			} else {
				string = description;
			}
		} else {
			string = description.length > 0 ? description : reason;
		}
		
		if(suggestion) {
			string = [string stringByAppendingFormat: @" %@", suggestion];
		}
		string = [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
		
		if(![strings containsObject:string] && string != nil) {
			/// we avoid redundant error messages.
			[strings addObject:string];
		}
	}
	
	NSString *log = [strings componentsJoinedByString:@"\n"];
	[self setLogWindowText:log];
	return log;
}


- (void)showAlertForError:(NSError *)error {
	NSAlert *alert = [NSAlert alertWithError:error];
	NSArray *errors = error.userInfo[NSDetailedErrorsKey];
	NSString *log;
	if(errors.count > 0) {
		[alert addButtonWithTitle:@"Show Error Log"];
		[alert addButtonWithTitle:@"Close"];
		log = [self populateErrorLogWithError:error];
	}
	[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
		if(returnCode == NSAlertFirstButtonReturn && log.length > 0) {
			[self showErrorLogWindow:self];
		}
	}];
}


- (BOOL)windowShouldClose:(NSWindow *)sender {
	if(sender == self.window) {
		/// We quit if the main window closes.
		[NSApp terminate:self];
		return NO; /// The window will close when the app quits, but if the app didn't (for some reason), it should not.
	}
	return YES;
}



@end
