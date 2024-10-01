//
//  PanelListController.m
//  STRyper
//
//  Created by Jean Peccoud on 07/08/2022.
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



#import "PanelListController.h"
#import "Panel.h"
#import "Mmarker.h"
#import "MainWindowController.h"
#import "PanelFolder.h"
#import "SampleTableController.h"

@implementation PanelListController {
	IBOutlet MarkerTableController *_markerTableController;
	__weak IBOutlet NSPopUpButton *applyPanelButton;
	NSMutableArray *draggedMarkers;
	
}


+ (instancetype)sharedController {
	static PanelListController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = self.new;
	});
	
	return controller;
}


- (NSNibName)nibName {
	return @"MarkerTab";
}


- (NSString *)entityName {
	return PanelFolder.entity.name;
}


- (void)viewDidLoad {
    [super viewDidLoad];
	
	[outlineView registerForDraggedTypes:@[FolderDragType, MarkerPasteboardType]];   ///so we can drag a panel between folders (and apply it to sample by dragging to the sample table)
	
	SampleTableController *sharedController = SampleTableController.sharedController;
	for(NSMenuItem *item in applyPanelButton.menu.itemArray) {
		if(item.tag == 1) {
			[item bind:NSEnabledBinding toObject:sharedController withKeyPath:@"samples.arrangedObjects.@count" options:nil];
		} else if(item.tag == 2) {
			[item bind:NSEnabledBinding toObject:sharedController withKeyPath:@"samples.selectedObjects.@count" options:nil];
		}
	}
	
}



# pragma mark - management of drops onto the table


- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index {
	
	NSPasteboard *pboard = info.draggingPasteboard;
	if([pboard.types containsObject:MarkerPasteboardType]) {	/// markers are dragged (from the marker tableview)
		Folder *destination = [self _folderForItem:item];
		if(!destination.isPanel || destination == self.selectedFolder) {
			return NSDragOperationNone;							/// markers cannot be dropped into their own folders (which must be the one selected)
		}
		return NSDragOperationCopy;
	}
	return [super outlineView:outlineView validateDrop:info proposedItem:item proposedChildIndex:index];
}


- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index {
	NSPasteboard *pboard = info.draggingPasteboard;
	if ([pboard.types containsObject:MarkerPasteboardType]) {  /// markers are dragged between folders
		Folder *destination = [self _folderForItem:item];
		if(destination == self.selectedFolder) {
			return NO;
		}
		return [self addMarkersFromPasteBoard:pboard ToPanel:(Panel *)destination];
	}

	return [super outlineView:outlineView acceptDrop:info item:item childIndex:index];
}


# pragma mark - copy / pasting markers


-(IBAction)paste:(id)sender {
	Panel *selectedPanel = self.selectedFolder;
	NSPasteboard *pboard = NSPasteboard.generalPasteboard;
	if(selectedPanel.isPanel && [pboard.types containsObject:MarkerPasteboardType]) {
		[self addMarkersFromPasteBoard:pboard ToPanel:selectedPanel];
	}
}



/// Adds marker retrieved from a paste board to a panel and returns whether at least one marker could be added.
///
/// - Parameters:
///   - pboard: A pasteboard.
///   - destination: A panel.
-(BOOL) addMarkersFromPasteBoard:(NSPasteboard *)pboard ToPanel:(Panel *)destination {
	if(destination == nil || !destination.isPanel) {
		return NO;
	}
	NSError *error;
	if(destination.objectID.isTemporaryID) {
		[self.managedObjectContext obtainPermanentIDsForObjects:@[destination] error:nil];
	}
	/// We paste in another context that has no undo manager as we validate whether markers can be added to the panel.
	/// By default, decoded objects are materialized in this context (see `initWithCoder:` of CodingObject.m)
	NSManagedObjectContext *MOC = AppDelegate.sharedInstance.childContext;
	[MOC reset];

	Panel *panel = [MOC existingObjectWithID:destination.objectID error:&error];
	NSUInteger nCopiedMarkers = 0;
	NSMutableArray *validationErrors = NSMutableArray.new;
	
	if(error) {
		error = [NSError errorWithDescription:@"The marker(s) could not be added to the panel." suggestion:@"An error occurred in the database."];
	} else {
		for(NSPasteboardItem *item in pboard.pasteboardItems) {
			NSData *archivedMarker = [item dataForType:MarkerPasteboardType];
			if(archivedMarker) {
				Mmarker *marker = [NSKeyedUnarchiver unarchivedObjectOfClass:Mmarker.class fromData:archivedMarker error:&error];
				if(!error) {
					NSError *validationError;
					[marker validateValue:&panel forKey:@"panel" error:&validationError];
					if(!validationError) {
						[marker managedObjectOriginal_setPanel:panel];
						nCopiedMarkers++;
					} else {
						[MOC deleteObject:marker];
						[validationErrors addObject:validationError];
					}
				}
			}
		}
	}
	
	if(nCopiedMarkers > 0) {
		NSString *action = [pboard.name isEqualToString: NSPasteboardNameDrag]? @"Transfer Marker" : @"Paste Marker";
		if(nCopiedMarkers > 1) {
			action = [action stringByAppendingString:@"s"];
		}
		[self.undoManager setActionName:action];
		[MOC save:&error];
		[AppDelegate.sharedInstance saveAction:self];
	}

	NSUInteger errorCounts = validationErrors.count;
	if(errorCounts > 0) {
		if(errorCounts == 1) {
			error = validationErrors.firstObject;
		} else {
			NSString *description = [NSString stringWithFormat:@"%ld markers could not be added to the panel.", errorCounts];
			error = [NSError errorWithDomain:STRyperErrorDomain
										code:NSManagedObjectValidationError
									userInfo:@{NSDetailedErrorsKey: [NSArray arrayWithArray:validationErrors],
											   NSLocalizedDescriptionKey: NSLocalizedString(description, nil),
											   NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"See the error log for details.", nil)
												}];
		}
	}
	if(error) {
		[MainWindowController.sharedController showAlertForError:error];
	}
	
	return nCopiedMarkers > 0;
}



- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	BOOL validated = [super validateMenuItem:menuItem];
	if(!validated) {
		return NO;
	}
	
	if(menuItem.action == @selector(paste:)) {
		NSPasteboard *pboard = NSPasteboard.generalPasteboard;
		return self.selectedFolder.isPanel && [pboard.types containsObject:MarkerPasteboardType];
	}
	
	PanelFolder *targetFolder = [self _targetFolderOfSender:menuItem];
	if(targetFolder.isPanel) {
		if(menuItem.action == @selector(addFolder:) || menuItem.action == @selector(importPanels:)) {
			/// we can't add a folder or import a panel into a panel
			menuItem.hidden = YES;
			return NO;
		}
	} else if(menuItem.action == @selector(addFolder:)) {
		menuItem.hidden = NO;
		if(menuItem.tag == 4) { /// The item to add a panel
			menuItem.title = targetFolder? @"Add Panel" : @"New Panel";
		} else {
			menuItem.title = targetFolder? @"Add Subfolder" : @"New Folder";
		}
		return YES;
	}
	
	
	if(menuItem.action == @selector(exportSelection:)) {
		if(targetFolder.panels.count == 1) {
			menuItem.title = @"Export Panel to File…";
		} else if(targetFolder.panels.count > 1) {
			menuItem.title = @"Export Panels to File…";
		} else {
			menuItem.hidden = YES;
			return NO;
		}
	} else if(menuItem.action == @selector(importBinSet:)) {
		if(!targetFolder.isPanel || ((Panel *)targetFolder).markers.count == 0) {
			menuItem.hidden = YES;
			return NO;
		}
	}
	
	menuItem.hidden = NO;
	return YES;
}


- (NSAlert *)cautionAlertForRemovingItems:(NSArray *)items {
	Folder *folder = items.firstObject;
	
	if(folder.subfolders.count > 0) {
		/// we don't post an alert if the folder to remove is empty
		return [super cautionAlertForRemovingItems:items];
	} else if(folder.isPanel) {
		Panel *panel = (Panel *)folder;
		if(panel.markers.count >0) {
			return [super cautionAlertForRemovingItems:items];
		}
	}
	return nil;
}


- (NSString *)cautionAlertInformativeStringForItems:(NSArray *)items {
	Folder *folder = items.firstObject;
	if(folder.isPanel) {
		return @"All markers and associated genotypes will be removed. \nThis action can be undone.";
	}
	return @"All panels in the folder, their markers and associated genotypes will be removed. \nThis action can be undone.";
}


# pragma mark - panels import / export


- (IBAction)exportSelection:(id)sender {
	PanelFolder *folder = [self _targetFolderOfSender:sender];
	if(folder.panels.count > 0) {
		[self exportPanel:(Panel *)folder];
	}
}


- (void)exportPanel:(Panel *)panel {
	NSSavePanel* savePanel = NSSavePanel.savePanel;
	savePanel.prompt = panel.panels.count > 1? @"Export Panels" : @"Export Panel";

	savePanel.message = panel.isPanel? @"Export panel to a tab-delimited text file" : @"Export panel(s) to a tab-delimited text file";
	savePanel.nameFieldStringValue = panel.name;
	savePanel.allowedFileTypes = @[@"public.plain-text"];
	[savePanel beginSheetModalForWindow:outlineView.window completionHandler:^(NSInteger result){
		if (result == NSModalResponseOK) {
			NSURL* theFile = savePanel.URL;
			NSString *exportString = panel.exportString;
			NSError *error = nil;
			[exportString writeToURL:theFile atomically:YES encoding:NSUTF8StringEncoding error:&error];
			if(error) {
				[[NSAlert alertWithError:error] beginSheetModalForWindow:self.view.window
													   completionHandler:^(NSModalResponse returnCode) {
				}];
			}
		}
	}];
}


- (IBAction)importPanels:(id)sender {
	PanelFolder *folder = [[self targetItemsOfSender:sender] firstObject];
	if(folder.class != PanelFolder.class) {
		folder = (PanelFolder *)folder.parent;
	}
	
	if(!folder) {
		folder = self.rootFolder;
	}
	
	NSOpenPanel* openPanel = NSOpenPanel.openPanel;
	openPanel.prompt = @"Import";
	openPanel.canChooseDirectories = NO;
	openPanel.allowsMultipleSelection = NO;
	openPanel.message = @"Import panels from a text file";
	openPanel.allowedFileTypes = @[@"public.plain-text"];
	[openPanel beginSheetModalForWindow:self.view.window completionHandler:^(NSInteger result){
		if (result == NSModalResponseOK) {
			NSURL* url = openPanel.URLs.firstObject;
			[self importPanelsFromURL:url ToFolder:folder];
		}
	}];
}


- (void)importPanelsFromURL:(NSURL *) url ToFolder:(PanelFolder *)folder {
	NSError *error;
	NSWindow *window = self.view.window;
	
	AppDelegate *delegate = AppDelegate.sharedInstance;
	/// we import the panels in a temporary context on the main queue.
	NSManagedObjectContext *temporaryContext = delegate.newChildContextOnMainQueue;
	if(folder.objectID.isTemporaryID) {
		[folder.managedObjectContext obtainPermanentIDsForObjects:@[folder] error:&error];
	}
	folder = [temporaryContext existingObjectWithID:folder.objectID error:&error];
	if(error) {
		error = [NSError errorWithDescription:@"The panel(s) could not be imported because an error occurred in the database."
								   suggestion:@"You may quit the application and try again."];
		NSAlert *alert = [NSAlert alertWithError:error];
		[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
		}];
		return;
	}
	
	[folder addPanelsFromTextFile:url.path error:&error];
		
	if(error) {
		[MainWindowController.sharedController showAlertForError:error];
		return;
	}
			
	if(temporaryContext.hasChanges){
		[self.undoManager setActionName:@"Import Panels"];
		[temporaryContext save:&error];
		if(error) {
			error = [NSError errorWithDescription:@"The panel(s) could not be imported because an error occurred saving the database."
									   suggestion:@"You may quit the application and try again."];
			NSAlert *alert = [NSAlert alertWithError:error];
			[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
			}];
			return;
		}
				
		[AppDelegate.sharedInstance saveAction:self];
		
		/// We make sure that the tab showing or view is displayed if a folder is added.
		[MainWindowController.sharedController activateTabNumber:2];
	}
}


- (void)_addFolderToTable:(Folder *)folder {
	/// We make sure that the tab showing or view is displayed if a folder is added.
	[MainWindowController.sharedController activateTabNumber:2];
	[super _addFolderToTable:folder];
}



- (IBAction)importBinSet:(id)sender {
	Panel *panel = [[self targetItemsOfSender:sender] firstObject];
	if(panel.isPanel && panel.markers.count > 0) {
		NSOpenPanel* openPanel = NSOpenPanel.openPanel;
		openPanel.prompt = @"Import";
		openPanel.canChooseDirectories = NO;
		openPanel.allowsMultipleSelection = NO;
		openPanel.message = @"Import bin sets from a Genemapper file";
		openPanel.allowedFileTypes = @[@"public.plain-text"];
		[openPanel beginSheetModalForWindow:self.view.window completionHandler:^(NSInteger result){
			if (result == NSModalResponseOK) {
				NSURL* url = openPanel.URLs.firstObject;
				[self addBinSetFromURL:url toPanel:panel];
			}
		}];
	}
}


- (void) addBinSetFromURL:(NSURL *)url toPanel:(Panel *)panel {
	NSError *error;
	NSWindow *window = self.view.window;
	
	AppDelegate *delegate = AppDelegate.sharedInstance;
	/// we import the bin set in a temporary context on the main queue.
	NSManagedObjectContext *temporaryContext = delegate.newChildContextOnMainQueue;
	
	if(panel.objectID.isTemporaryID) {
		[panel.managedObjectContext obtainPermanentIDsForObjects:@[panel] error:&error];
	}
	
	panel = [temporaryContext existingObjectWithID:panel.objectID error:&error];
	if(error) {
		error = [NSError errorWithDescription:@"The bin set could not be imported because an error in the database."
								   suggestion:@"You may quit the application and try again."];
		NSAlert *alert = [NSAlert alertWithError:error];
		[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
		}];
		return;
	}
	
	[panel takeBinSetFromGenemapperFile:url.path error:&error];
	
	if(error) {
		[MainWindowController.sharedController showAlertForError:error];
		return;
	}
	
	if(temporaryContext.hasChanges){
		[self.undoManager setActionName:@"Import Bin Set"];
		[temporaryContext save:&error];
		if(error) {
			error = [NSError errorWithDescription:@"The bin set could not be imported because an error saving the database."
									   suggestion:@"You may quit the application and try again."];
			NSAlert *alert = [NSAlert alertWithError:error];
			[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
			}];
			return;
		}

		[AppDelegate.sharedInstance saveAction:self];
	}
}


-(IBAction)applyPanel:(NSMenuItem *)sender {
	Panel *selectedPanel = self.selectedFolder;
	SampleTableController *sharedController = SampleTableController.sharedController;
	if(selectedPanel.isPanel && sharedController) {
		if(sender.tag == 1) {
			[sharedController applyPanel:selectedPanel toSamples:sharedController.samples.arrangedObjects];
		} else if(sender.tag == 2) {
			[sharedController applyPanel:selectedPanel toSamples:sharedController.samples.selectedObjects];
		}
	}
}

@end
