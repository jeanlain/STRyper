//
//  SourceItemController.m
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
#import "FileImporter.h"



@implementation MainWindowController {
	/// Outlet used to populate the tab view by adding tabs, which are loaded from other nibs.
	/// We could reach the desired view in code by enumerating subviews, but it seems safer this way
	__weak IBOutlet NSTabView *tabView;
	
	/// backs the ``errorLogWindow`` property.
	IBOutlet NSPanel *_errorLogWindow;
}


typedef enum bottomTab : NSUInteger {		/// the number of the tab in the bottom tab view
	sampleInspectorTab,
	genotypeTab,
	markerTab,
	sizeStandardTab
} bottomTab;


@synthesize mainSplitViewController = _mainSplitViewController,
verticalSplitViewController = _verticalSplitViewController,
errorLogWindow = _errorLogWindow;



+ (instancetype)sharedController {
	static MainWindowController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = [[self alloc] init];
	});
	return controller;
}


- (NSNibName)windowNibName {
	return @"MainWindow";
}


- (void)windowDidLoad {
	[super windowDidLoad];
	NSWindow *window = self.window;
	[window makeKeyAndOrderFront:self];
	[window makeMainWindow];
	window.acceptsMouseMovedEvents = NO;
	
	
	if(!self.mainSplitViewController) {
		NSLog(@"failed to load the main split view.");
		abort();
	}
	
		
	///Adding the sample inspector to the tab view.
	SampleInspectorController *sampleInspectorController = SampleInspectorController.sharedController;
	if(sampleInspectorController.view) {
		NSTabViewItem *item = NSTabViewItem.new;
		item.view =  sampleInspectorController.view;
		[tabView addTabViewItem:item];
		[sampleInspectorController bind:@"samples" toObject:SampleTableController.sharedController.tableContent withKeyPath:@"selectedObjects" options:nil];
	} else {
		NSLog(@"failed to load the sample table.");
		abort();
	}
		
	///Adding the genotype tab.
	GenotypeTableController *genotypeTableController = GenotypeTableController.sharedController;
	if(genotypeTableController.view) {
		NSTabViewItem *item = NSTabViewItem.new;
		item.view =  genotypeTableController.view;
		[tabView addTabViewItem:item];
		
	} else {
		NSLog(@"failed to load the genotype table.");
		abort();
	}
	
	
	///Adding the panel + marker tab.
	PanelListController *panelListController = PanelListController.sharedController;
	if(panelListController.view) {
		NSTabViewItem *item = NSTabViewItem.new;
		item.view = panelListController.view;;
		[tabView addTabViewItem:item];
	} else {
		NSLog(@"failed to load the panel list.");
		abort();
	}
	
	
	///Adding the size standard tab.
	SizeStandardTableController *sizeStandardTableController = SizeStandardTableController.sharedController;
	if(sizeStandardTableController.view) {
		NSTabViewItem *item = NSTabViewItem.new;
		item.view = sizeStandardTableController.view;;
		[tabView addTabViewItem:item];
	} else {
		NSLog(@"failed to load the size standard table.");
		abort();
	}
	
	/// To remember which tab is shown and to synchronize the NSSegmentedControl button activating tab and the tabView, we use a property set in user defaults.
	[tabView bind:NSSelectedIndexBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:BottomTab options:nil];
	
	
	if(!SampleSearchHelper.sharedHelper) {
		/// we init the search controller as must perform the search in case there are smart folder in the database
		NSLog(@"failed to load the search helper.");
		/// but we don't abort if it is absent.
	}
}


- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	/// Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
	return ((AppDelegate *)NSApp.delegate).managedObjectContext.undoManager;
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
		} else {
			return nil;
		}
		/// the middle pane, which is itself a vertical split view
		if(self.verticalSplitViewController.view) {
			NSSplitViewItem *item = [NSSplitViewItem contentListWithViewController:self.verticalSplitViewController];
			item.minimumThickness = 250.0;
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
			float thickness = 420;
			if(button) {
				thickness = NSMaxX(button.frame) + 5;
			}
			item.minimumThickness = thickness;
			item.collapseBehavior = NSSplitViewItemCollapseBehaviorPreferResizingSiblingsWithFixedSplitView;	/// this doesn't appear to work consistently as revealing the bottom pane may sometimes increase the window height while there is still space
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
	if(controller == self.sourceController) {
		return;
	}
	_sourceController = controller;
		
	NSTableView *activeTableView = controller.tableView;
	if(activeTableView.window.firstResponder != activeTableView) {
		[activeTableView.window makeFirstResponder:activeTableView];
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
	
	if(menuItem.action == @selector(showImportSamplePanel:)) {
		return FolderListController.sharedController.canImportSamples;
	}
	
	if(menuItem.action == @selector(editSmartFolder:)) {
		return [FolderListController.sharedController validateMenuItem:menuItem];
	}
	
	if(menuItem.action == @selector(toggleLeftPane:)) {
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
		/// we show the tick-mark if the menu corresponds to the tab that is active and if the bottom pane is not collapsed. The tag of the menu refers to the index of the tab
		BOOL collapsed = self.verticalSplitViewController.splitViewItems.lastObject.isCollapsed;
		menuItem.state = menuItem.tag == [tabView.tabViewItems indexOfObject: tabView.selectedTabViewItem] && !collapsed? NSControlStateValueOn : NSControlStateValueOff;
		return YES;
	}
	
	if(menuItem.action == @selector(showErrorLogWindow:)) {
		menuItem.state = self.errorLogWindow.isVisible? NSControlStateValueOn : NSControlStateValueOff;
		return YES;
	}
	
	if(menuItem.action == @selector(topFluoMode:)) {
		/// Menu items that call this has a tag corresponding to the TraceTopFluoMode of the use default.
		/// We add a check mark to the menu item it it corresponds to the current mode
		TopFluoMode fluoMode = [NSUserDefaults.standardUserDefaults integerForKey:TraceTopFluoMode];
		menuItem.state = menuItem.tag == fluoMode? NSControlStateValueOn : NSControlStateValueOff;
		return YES;
	}
	
	if(menuItem.action == @selector(stackMode:)) {
		/// Menu items that call this have a tag corresponding to the TraceStackMode of the use default.
		/// We add a check mark to the menu item it it corresponds to the current mode
		TopFluoMode fluoMode = [NSUserDefaults.standardUserDefaults integerForKey:TraceStackMode];
		menuItem.state = menuItem.tag == fluoMode? NSControlStateValueOn : NSControlStateValueOff;
		return YES;
	}
	
	return YES;
}


- (void)deleteSelection:(id)sender {
	/// We implement this only to be sent the validateMenuItem message to hide the item
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


-(void)showImportSamplePanel:(id)sender {
	[SampleTableController.sharedController showImportSamplePanel:sender];
}


-(void)toggleLeftPane:(id)sender {
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


- (void)keyDown:(NSEvent *)event {
	unichar key = [event.charactersIgnoringModifiers characterAtIndex:0];
	/// we send any up/down arrow key event to the active tableview
	if ((key == NSUpArrowFunctionKey || key == NSDownArrowFunctionKey) && self.sourceController.tableView) {
		[self.sourceController.tableView keyDown:event];
	}
}


/*
 /// an alternative method to update the undo/redo tooltips, but this method is deprecated
- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data {
	NSUndoManager *undoManager = self.window.firstResponder.undoManager;
	if(tag == undoToolTipTag) {
		return undoManager.undoMenuItemTitle;
	}
	if(tag == redoToolTipTag) {
		return undoManager.redoMenuItemTitle;
	}
	return nil;
} */


- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
	NSToolbarItem *theItem = (NSToolbarItem *)item;
	if(item.action == @selector(toggleLeftPane:)) {
		NSToolbarItem *theItem = (NSToolbarItem *)item;
		theItem.toolTip = [self.mainSplitViewController.splitViewItems.firstObject isCollapsed]? @"Expand left pane" : @"Collapse left pane";
	} else if(item.action == @selector(toggleRightPane:)) {
		theItem.toolTip = [self.mainSplitViewController.splitViewItems.lastObject isCollapsed]? @"Expand detailed view" : @"Collapse detailed view";
	} else if(theItem.action == @selector(undoAction:)) {
		NSUndoManager *manager = self.window.firstResponder.undoManager;
		theItem.toolTip = manager.undoMenuItemTitle;
		return manager.canUndo;
	} else if(theItem.action == @selector(redoAction:)) {
		NSUndoManager *manager = self.window.firstResponder.undoManager;
		theItem.toolTip = manager.redoMenuItemTitle;
		return manager.canRedo;
	}
	return YES;
}


-(IBAction)undoAction:(id)sender {
	[self.window.firstResponder.undoManager undo];
}

-(IBAction)redoAction:(id)sender {
	[self.window.firstResponder.undoManager redo];
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
		
		if(![strings containsObject:string]) {
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
		/// we quit if the main window closes
		BOOL canQuit = [NSApp.delegate applicationShouldTerminate:NSApp] == NSTerminateNow;
		if(canQuit) {
			[NSApp terminate:self];
		}
		return canQuit;
	}
	return YES;
}



@end
