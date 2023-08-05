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
	
	/// Toolbar items for which we set tooltips.
	NSSet<NSToolbarItem *> *toolBarItems;
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


- (instancetype)init {
	return [super initWithWindowNibName:@"MainWindow"];
}


- (void)windowDidLoad {
	[super windowDidLoad];
	NSWindow *window = self.window;
	[window orderFrontRegardless];  ///makeKeyAndOrderFront would generate a warning
	[window makeKeyWindow];
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
	
	
	if(!SampleSearchHelper.sharedHelper) {
		/// we init the search controller as must perform the search in case there are smart folder in the database
		NSLog(@"failed to load the search helper.");
		/// but we don't abort if it is absent.
	}
	
	/// To remember which tab is shown and to synchronize the NSSegmentedControl button activating tab and the tabView, we use a property set in user defaults.
	[tabView bind:NSSelectedIndexBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:BottomTab options:nil];
	
	/// We store the toolbar items containing the undo/redo buttons, to set their tooltips depending an undo/redo action names
	toolBarItems = NSSet.new;
	for(NSToolbarItem *item in self.window.toolbar.items) {
		if(item.action == @selector(undo:) || item.action == @selector(redo:)) {
			toolBarItems = [toolBarItems setByAddingObject:item];
		}
	}
	
	/*
	 /// We add tooltip rectangles to undo/redo toolbar items, so that they indicate the undo/redo action names when hovered. For this, we need to access their view.
	 /// These cannot be accessed directly, as the `view` property of a toolbar item returns nil if it is the default view.
	 /// We find them by enumerating all views in the toolbar. The toolbar is not part of the window's content view, but of a superview
	 NSMutableArray *views = [NSMutableArray arrayWithArray: self.window.contentView.superview.subviews];
	 [views removeObject:self.window.contentView];
	 
	 for(NSView *view in views) {
		 [self addToolTipRectsToSubviewsOf:view];
	 }
	 
 }

 /// Recursively scans the subviews of `view` to add tooltip rectangle to undo/redo buttons of the toolbar items

 /// This is because the default `view` of a toolbar item cannot be accessed, so we scan all subviews to locate them
 /// A dedicated method was needed as it is called recursively to traverse all subviews of the view
 -(void) addToolTipRectsToSubviewsOf:(NSView *)view {
	 for(NSButton *button in view.subviews) {
		 if([button isKindOfClass:NSButton.class]) {
			 if(button.action == @selector(undo:)) {
				 undoToolTipTag = [button addToolTipRect:button.bounds owner:self userData:nil];
			 } else if(button.action == @selector(redo:)) {
				 redoToolTipTag = [button addToolTipRect:button.bounds owner:self userData:nil];
			 }
			 if(undoToolTipTag != 0 && redoToolTipTag != 0) {
				 return;
			 }
		 } else {
			 [self addToolTipRectsToSubviewsOf:button];
*/
	
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
		if(detailedViewController.view) {
			
			[detailedViewController.tableView bind:NSSortDescriptorsBinding toObject:SampleTableController.sharedController.samples withKeyPath:NSStringFromSelector(@selector(sortDescriptors)) options:nil];
			
			/// we bind the contents to show in the detailed view to the selected objects of the source controller.
			/// The detailed view will then show the selected objects from the various sources
			[detailedViewController bind:@"contentArray" toObject:self withKeyPath:@"sourceController.tableContent.selectedObjects" options:nil];

			[detailedViewController bind:@"stackMode" toObject:NSUserDefaults.standardUserDefaults withKeyPath:TraceStackMode options:nil];
			[detailedViewController bind:@"numberOfRowsPerWindow" toObject:NSUserDefaults.standardUserDefaults withKeyPath:TraceRowsPerWindow options:nil];
			[detailedViewController bind:@"synchronizeViews" toObject:NSUserDefaults.standardUserDefaults withKeyPath:SynchronizeViews options:nil];
			[detailedViewController bind:@"topFluoMode" toObject:NSUserDefaults.standardUserDefaults withKeyPath:TraceTopFluoMode options:nil];

			NSSplitViewItem *item = [NSSplitViewItem splitViewItemWithViewController:detailedViewController];
			item.canCollapse = YES;
			/// we determine its minimum width based on the button shown at the bottom (which should not be clipped)
			NSView *button = [detailedViewController.view viewWithTag:-5];
			float thickness = 420;
			if(button) {
				thickness = NSMaxX(button.frame) + 5;
			}
			item.minimumThickness = thickness;
			item.collapseBehavior = NSSplitViewItemCollapseBehaviorPreferResizingSiblingsWithFixedSplitView;	/// this doesn't appear to work consistently as revealing the bottom pane may sometimes increase the window height while there is still space
			[_mainSplitViewController addSplitViewItem:item];
			
			mainSplitView.autosaveName = [mainSplitView.identifier stringByAppendingString:@"Configuration"];
		} else {
			return nil;
		}
		
	}
	return _mainSplitViewController;
}


- (NSSplitViewController *)verticalSplitViewController {
	if(!_verticalSplitViewController) {
		
		NSView *bottomPane = tabView.superview;						/// the bottom pane of the controller's split view (which contains the tab view)
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


# pragma mark -
# pragma mark UI validation and action messages


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {

	if(menuItem.action == @selector(deleteBackward:)) {
		menuItem.title = @"Delete";
		menuItem.hidden = YES;
		return NO;
	}
	
	if(menuItem.action == @selector(showImportSamplePanel:)) {
		return FolderListController.sharedController.canImportSamples;
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
		/// we show the tick-mark if the menu corresponds to the tab that is active. The tag of the menu refers to the index of the tab
		menuItem.state = menuItem.tag == [tabView.tabViewItems indexOfObject: tabView.selectedTabViewItem]? NSControlStateValueOn : NSControlStateValueOff;
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


-(void)removeItem:(id)sender {
	
}


- (void)deleteBackward:(id)sender {
	
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

		/// This is not elegant, but we also use this method to update the tooltip of undo/redo toolbar items, which dont send this message (their targets is the first responder, not us).
		/// This is still an appropriate place to update their tooltip, since this message is sent at any action affecting the window.
		///
		/// We do this because I see no way to call addToolTipForRect: on the button shown on an NSToolBarItem. This button is not accessible (returns nil) if it is the default one.
		/// Using a custom button for the item would work but this button would not have the desired properties of the default button, which uses a private class.
		/// So I don't see how to update the tooltip only when it shows (via stringForTooltip:), which would have been the desired solution. 
		/// Alternatively, we could register to `NSUndoManagerCheckpointNotification`, but this is sent too often to my taste.
		for(NSToolbarItem *item in toolBarItems) {
			SEL action = item.action;
			NSUndoManager *undoManager = self.window.firstResponder.undoManager;
			if(action == @selector(undo:)) {
				item.toolTip = undoManager.undoMenuItemTitle;
			} else {
				item.toolTip = undoManager.redoMenuItemTitle;
			}
		}
	} else if(item.action == @selector(toggleRightPane:)) {
		theItem.toolTip = [self.mainSplitViewController.splitViewItems.lastObject isCollapsed]? @"Expand detailed view" : @"Collapse detailed view";
	}
	return YES;
}


-(void)undo:(id)sender {
	/// this is only to avoid an "unknown selector" warning)
}

-(void)redo:(id)sender {
	/// this is only to avoid an "unknown selector" warning)
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
					string = [description stringByAppendingFormat:@"\t%@", reason];
				}
			} else {
				string = description;
			}
		} else {
			string = description.length > 0 ? description : reason;
		}
		
		if(!suggestion) {
			suggestion = @"";
		}
		string = [string stringByAppendingFormat: @"\t%@", suggestion];
		
		if(![strings containsObject:string]) {
			/// we avoid redundant error messages.
			[strings addObject:string];
		}
	}
	
	NSString *log = NSString.new;
	for(NSString *string in strings) {
		log = [log stringByAppendingFormat:@"%@\n", string];
	}
	
	[self setLogWindowText:log];
	return log;
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
