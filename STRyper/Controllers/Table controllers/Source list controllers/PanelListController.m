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

@implementation PanelListController {
	IBOutlet MarkerTableController *_markerTableController;
	NSMutableArray *draggedMarkers;
	
}


+ (instancetype)sharedController {
	static PanelListController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = [[self alloc] init];
	});
	
	return controller;
}

- (instancetype)init {
	return [super initWithNibName:@"MarkerTab" bundle:nil];
}


- (NSString *)entityName {
	return PanelFolder.entity.name;
}


- (void)viewDidLoad {
    [super viewDidLoad];
	
	[outlineView registerForDraggedTypes:@[FolderDragType, MarkerPasteboardType]];   ///so we can drag a panel between folders (and apply it to sample by dragging to the sample table)
	
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



-(BOOL) addMarkersFromPasteBoard:(NSPasteboard *)pboard ToPanel:(Panel *)destination {
	if(destination == nil || !destination.isPanel) {
		return NO;
	}
	NSError *error;
	if(destination.objectID.isTemporaryID) {
		[self.managedObjectContext obtainPermanentIDsForObjects:@[destination] error:nil];
	}
	/// we paste in another context that has no undo manager (as we may not validate the transfer of copied markers, hence discard the copies)
	/// by default, decoded objects are materialized in this context (seen initWithCoder: of CodingObject.m)
	NSManagedObjectContext *MOC = ((AppDelegate *)NSApp.delegate).childContext;
	[MOC reset];
	/// we make sure the state of the destination panel in this context reflects its state in the view context
	Panel *panel = [MOC existingObjectWithID:destination.objectID error:&error];
	NSInteger nCopiedMarkers = 0;
	if(error) {
		error = [NSError errorWithDescription:@"The marker(s) could not be copied." suggestion:@"An error occurred with the database."];
	} else {
		for(NSPasteboardItem *item in pboard.pasteboardItems) {
			NSData *archivedMarker = [item dataForType:MarkerPasteboardType];
			if(archivedMarker) {
				Mmarker *marker = [NSKeyedUnarchiver unarchivedObjectOfClass:Mmarker.class fromData:archivedMarker error:&error];
				if(!error) {
					[marker validateValue:&panel forKey:@"panel" error:&error];
					if(!error) {
						marker.panel = panel;
						nCopiedMarkers++;
						[MOC save:&error];
					}
				}
			}
		}
	}
	
	if(!error) {
		[(AppDelegate *)NSApp.delegate saveAction:self];
		NSString *action = [pboard.name isEqualToString: NSPasteboardNameDrag]? @"Transfer Marker" : @"Paste Marker";
		if(nCopiedMarkers > 1) {
			action = [action stringByAppendingString:@"s"];
		}
		[self.undoManager setActionName:action];
		return YES;
	}
	[[NSAlert alertWithError:error] beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
	}];
	return NO;
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
	
	if(menuItem.topMenu == outlineView.menu) {
		/// a menu item belonging to the outline view's contextual menu. This check isn't very future-proof…
		PanelFolder *clickedPanel = [self _targetFolderOfSender:menuItem];
		if(clickedPanel.isPanel) {					/// a panel is clicked.
			if(menuItem.action == @selector(addFolder:) || menuItem.action == @selector(importPanel:)) {
				/// we can't add a folder or import a panel into a panel
				menuItem.hidden = YES;
				return NO;
			}
		} else {
			if(menuItem.action == @selector(exportSelection:)) {
				/// we can't export a folder that isn't a panel
				menuItem.hidden = YES;
				return NO;
			}
		}
		return YES;
	}
	
	if(menuItem.action == @selector(exportSelection:)) {
		Folder *folder = self.selectedFolder;
		if(folder.isPanel) {
			menuItem.title = @"Export Panel…";
			return YES;
		} else {
			return NO;
		}
	}
	
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


+ (NSString *)cautionAlertInformativeStringForItems:(NSArray *)items {
	Folder *folder = items.firstObject;
	if(folder.isPanel) {
		return @"All markers and associated genotypes will be removed. \nThis action can be undone.";
	}
	return @"All panels in the folder, their markers and associated genotypes will be removed. \nThis action can be undone.";
}


# pragma mark - panels import / export


- (IBAction)exportSelection:(id)sender {
	Folder *folder = [self _targetFolderOfSender:sender];
	if(folder.isPanel) {
		[self exportPanel:(Panel *)folder];
	}
}


- (void)exportPanel:(Panel *)panel {
	NSSavePanel* savePanel = NSSavePanel.savePanel;
	savePanel.prompt = @"Export panel";
	savePanel.message = @"Export panel to a tab-delimited text file";
	savePanel.nameFieldStringValue = panel.name;
	savePanel.allowedFileTypes = @[@"public.plain-text"];
	[savePanel beginSheetModalForWindow:outlineView.window completionHandler:^(NSInteger result){
		if (result == NSModalResponseOK) {
			NSURL* theFile = savePanel.URL;
			NSString *exportString = panel.stringRepresentation;
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


- (IBAction)importPanel:(id)sender {
	PanelFolder *folder = [[self targetItemsOfSender:sender] firstObject];
	if(folder.class != PanelFolder.class) {
		folder = (PanelFolder *)self.rootFolder;
	}
	NSOpenPanel* openPanel = NSOpenPanel.openPanel;
	openPanel.prompt = @"Import";
	openPanel.canChooseDirectories = NO;
	openPanel.allowsMultipleSelection = NO;
	openPanel.message = @"Import panel from a text file";
	openPanel.allowedFileTypes = @[@"public.plain-text"];
	[openPanel beginSheetModalForWindow:self.view.window completionHandler:^(NSInteger result){
		if (result == NSModalResponseOK) {
			NSURL* url = openPanel.URLs.firstObject;
			[self importPanelFromURL:url ToFolder:folder];
		}
	}];
}


- (void)importPanelFromURL:(NSURL *) url ToFolder:(PanelFolder *)folder {
	NSError *error;
	NSWindow *window = self.view.window;
	
	AppDelegate *delegate = (AppDelegate *)NSApp.delegate;
	/// we import the panel in a temporary context on the main queue.
	NSManagedObjectContext *temporaryContext = delegate.newChildContextOnMainQueue;

	Panel *newPanel = [Panel panelFromTextFile:url.path insertInContext:temporaryContext error:&error];
	
	if(error) {
		NSAlert *alert = [NSAlert alertWithError:error];
		NSString *log = [MainWindowController.sharedController populateErrorLogWithError:error];
		if(log.length >0) {
			[alert addButtonWithTitle:@"Show Error Log"];
			[alert addButtonWithTitle:@"Close"];
		}
		[alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
			if(returnCode == NSAlertFirstButtonReturn && log.length > 0) {
				[MainWindowController.sharedController showErrorLogWindow:self];
			}
		}];
		return;
	}
	
	[temporaryContext obtainPermanentIDsForObjects:@[newPanel] error:nil];
		
	if(temporaryContext.hasChanges){
		[temporaryContext save:&error];
	}
	if(error) {
		NSAlert *alert = [NSAlert alertWithError:error];
		[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
		}];
		return;
	}
	
	newPanel = [self.managedObjectContext existingObjectWithID:newPanel.objectID error:&error];
	
	if(error) {
		error = [NSError errorWithDescription:@"The panel could not be imported because an error occurred when saving it to the database."
								   suggestion:@"You may quit the application and try again."];
		NSAlert *alert = [NSAlert alertWithError:error];
		[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
		}];
		return;
	}

	newPanel.parent = folder;
	[newPanel autoName];
	[self _addFolderToTable:newPanel];
	[self selectFolder:newPanel];
	[self.undoManager setActionName:@"Import Panel"];

	[(AppDelegate *)NSApp.delegate saveAction:self];

}




@end
